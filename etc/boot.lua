POPSLDR_VER = "v1.1.1-dev-EXP93"

--- Processes a HDD full path into its components.
--- Supports both explicit PFS paths (`hdd0:__system:pfs:/osd110/hosdsys.elf`)
--- and raw OPL-style paths (`hdd0:+OPL/APPS/PS1_POPSLOADER/POPSLOADER.ELF`).
---@param PATH string
---@return string mountpart: will return partition path for mounting (`hdd0:__system`)
---@return string pfsindx: will return pfs index (`pfs:`)
---@return string filepath: will return path to file when partition gets mounted (`pfs:/osd110/hosdsys.elf`)
function GetMountData(PATH)
  local candidate = tostring(PATH or "")
  local device, partition, pfsdev, suffix = string.match(candidate, "^([Hh][Dd][Dd]%d):([^:]+):([Pp][Ff][Ss]%d*):(.+)$")
  if device ~= nil and partition ~= nil and pfsdev ~= nil and suffix ~= nil then
    if string.sub(suffix, 1, 1) ~= "/" then
      suffix = "/"..suffix
    end
    return string.format("%s:%s", device, partition), string.lower(pfsdev)..":", string.lower(pfsdev)..":"..suffix
  end

  device, partition, suffix = string.match(candidate, "^([Hh][Dd][Dd]%d):/+([^/]+)/(.+)$")
  if device == nil or partition == nil then
    device, partition, suffix = string.match(candidate, "^([Hh][Dd][Dd]%d):([^:/]+)/(.+)$")
  end
  if device ~= nil and partition ~= nil and suffix ~= nil then
    suffix = string.gsub(suffix, "^/+", "")
    return string.format("%s:%s", device, partition), "pfs1:", "pfs1:/"..suffix
  end

  return "", "", ""
end


-- Default to "" so a launcher that passes argc==0 (argv0 -> nil) can't crash the
-- string.find calls below into the boot error screen; "" just falls through to the
-- normal mass/mc resolution path, same as any non-HDD/non-MX4SIO launcher.
local ARGV0 = System.GetArgv0() or ""
if string.find(ARGV0, "^hdd0:") then
  local MNTPART
  BOOTPATH = nil
  BOOT_HDD_MOUNTPART = nil
  BOOT_HDD_MOUNT_SLOT = nil
  BOOT_HDD_MOUNT_PREFIX = nil
  MNTPART, _, BOOTPATH = GetMountData(ARGV0)
  if string.find(BOOTPATH, "^pfs") then
    SUCCESS, MODULE, ID, RET = HDD.Initialize()
    if SUCCESS then
      System.sleep(2) -- lets give it time to get ready
      if HDD.MountPartition(MNTPART, 1) then -- mount to "pfs1:" and NEVER USE IT FOR ANYTHING ELSE
        BOOT_HDD_MOUNTPART = MNTPART
        BOOT_HDD_MOUNT_SLOT = 1
        BOOT_HDD_MOUNT_PREFIX = "pfs1:/"
        BOOTPATH, _, _ = string.match(BOOTPATH, "(.-)([^/]-([^%.]+))$")
        -- Normalize whatever pfs slot prefix came from ARGV0 to the
        -- actual mount slot we just established. GetMountData preserves
        -- the original prefix from ARGV0, which can be slot-less ("pfs:")
        -- when launchers don't include a digit -- e.g. wLaunchELF passing
        -- "hdd0:_OPL:pfs:/APPS/PS1_POPSLOADER/POPSLOADER.ELF". But we
        -- always mount to pfs1: above. Lua's cwd must match the mount
        -- or relative-path file I/O (and the settings sidecar at
        -- APP_DIR/.pldrs) fails: Nuno 2026-05-26 saw "pfs:/APPS/PS1_
        -- POPSLOADER/.pldrs may be read-only" because cwd was pfs:/...
        -- and pfs: isn't a real mount.
        BOOTPATH = string.gsub(BOOTPATH, "^[Pp][Ff][Ss]%d*:", "pfs1:")
        System.currentDirectory(BOOTPATH)
      end
    end
  end
end

BOOT_MX4SIO_PREFIX = nil
BOOT_MX4SIO_PROBE_RESULT = nil
if string.find(ARGV0, "^[Mm][Xx]4[Ss][Ii][Oo]") then
  -- MX4SIO boot: the mx4sio:/ argv0 prefix is the BDM device-kind
  -- label, NOT a writable fileXio mount. The launcher (wLaunchELF,
  -- HOSDmenu, NHDDL, etc.) was able to load POPSLOADER.ELF through
  -- some kernel-side indirection, but fileXio file writes against
  -- mx4sio:/<path> fail with "may be read-only" (Nuno 2026-05-28 PM
  -- hardware: `mx4sio:/APPS/PS1_POPSLOADER/.pldrs may be read-only`).
  --
  -- The writable filesystem path is the mass*:/ slot where bdmfs_fatfs
  -- mounts the SD card once mx4sio_bd has loaded. The slot is volatile
  -- (depends on hotplug + IRX load order), so we identify it
  -- dynamically by the same ioctl driver-name rule PR #472 uses for
  -- boot-device classification: sdc/mx4 ioctl => MX4SIO.
  --
  -- PR #472 also enforces at the C layer that mx4sio_bd requires
  -- usbmass_bd to be loaded first (maintainer rule: "mx4sio will need
  -- the usb drivers to activate before it with it"), so this branch
  -- calls System.ensureUsbMass before System.initMX4SIO.
  if type(System) == "table" and type(System.ensureUsbMass) == "function" then
    pcall(System.ensureUsbMass)
  end
  if type(System) == "table" and type(System.initMX4SIO) == "function" then
    pcall(System.initMX4SIO)
  end
  -- Initial settle for the MX4SIO double-ping. PR #476 had a single
  -- 1-second sleep + single scan; Nuno's 2026-05-28 PM hardware test
  -- showed that's not enough on real hardware -- the BDM didn't see
  -- the SD card on the first probe, the scan returned nothing, the
  -- cwd translation never happened, and settings still tried to write
  -- to mx4sio:/<path>/.pldrs. PLDR.InitMX4SIOPopsRoot uses a 3-attempt
  -- retry with sleep(1) between failures (~3s worst case) -- mirror
  -- that here so the scan succeeds even when the first probe misses.
  System.sleep(1)
  local function scan_for_mx4sio_root()
    if type(System.refreshMassBackends) == "function" then
      pcall(System.refreshMassBackends)
    end
    if type(System.getMassMountDriver) ~= "function" then
      return nil, "no_getMassMountDriver"
    end
    for slot = 0, 9 do
      local root = (slot == 0) and "mass:/" or ("mass"..tostring(slot)..":/")
      local ok, driver = pcall(System.getMassMountDriver, root)
      if ok and type(driver) == "string" and driver ~= "" then
        local lowered = string.lower(driver)
        if string.find(lowered, "mx4", 1, true) ~= nil or string.find(lowered, "sdc", 1, true) ~= nil then
          return root, "found:"..root.."="..driver
        end
      end
    end
    return nil, "no_match"
  end
  local MX_ROOT = nil
  local probe_trace = {}
  for attempt = 1, 3 do
    local root, info = scan_for_mx4sio_root()
    probe_trace[#probe_trace + 1] = "a"..tostring(attempt)..":"..tostring(info or "nil")
    if root ~= nil then
      MX_ROOT = root
      break
    end
    if attempt < 3 then
      System.sleep(1)
    end
  end
  BOOT_MX4SIO_PROBE_RESULT = table.concat(probe_trace, ";")
  if MX_ROOT ~= nil then
    BOOT_MX4SIO_PREFIX = MX_ROOT
    -- Translate mx4sio:/<rel> argv0 directory to MX_ROOT/<rel>/.
    -- ResolveAppDirLocal in system.lua will see APP_DIR is mx4sio:/-
    -- prefixed and cwd is mass*:/ and prefer the cwd, so settings
    -- sidecar resolves to the writable mass*:/ root.
    local relpath = string.match(ARGV0, "^[Mm][Xx]4[Ss][Ii][Oo]%d*:/?(.*)$") or ""
    -- Strip the filename so cwd is the directory containing the ELF
    -- (matches what the HDD branch does for its BOOTPATH).
    local dir_rel = string.match(relpath, "^(.-)/[^/]*$")
    if dir_rel == nil then
      dir_rel = ""
    end
    local translated_cwd = MX_ROOT..string.gsub(dir_rel, "^/+", "")
    if string.sub(translated_cwd, -1) ~= "/" then
      translated_cwd = translated_cwd.."/"
    end
    System.currentDirectory(translated_cwd)
  end
end
GPAD = 0
Font.ftInit()
local BOOT_FONT_KEY = "fonts/Roboto-Regular.ttf"
local function load_boot_font_or_die()
  local h = Font.ftLoadEmbedded(BOOT_FONT_KEY)
  if type(h) ~= "number" then
    Screen.clear(Color.new(0,0,0))
    Font.fmLoad()
    Font.fmPrint(40, 40, 0.8, "FATAL: embedded boot font missing: "..BOOT_FONT_KEY, Color.new(255, 0, 0))
    Screen.flip()
    while true do end
  end
  return h
end

BFONT = load_boot_font_or_die()
SFONT = load_boot_font_or_die()
LFONT = load_boot_font_or_die()
Font.ftSetCharSize(BFONT, 800, 800)
Font.ftSetCharSize(SFONT, 600, 600)
Font.ftSetCharSize(LFONT, 900, 900)
function STOP() Screen.clear(Color.new(255,0,0)) Screen.flip() while true do end end

require("system")
