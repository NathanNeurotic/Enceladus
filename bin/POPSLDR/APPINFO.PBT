# SAS (Save Application Support) compliant BM Script
# Due to wildcard bug on memory card and mmce, bootdevice:/BM/SCRIPTS/DEFINEDROOTFOLDER.PBT must exist to work. Update as needed

# Change this information to describe the application and where it should be ran from for memcard (SAS) or other devices (SAS_NON_MC)
# SAS is the App folder name. SAS_NON_MC defines if app is in root of non-memcard device (non_mc:/$SAS$) or APP folder (non_mc:/APPS/$SAS$)
# This is so that you do not have to edit any info below line 28.
#
# Some devices are case sensitive! Make sure your case matches!
#
# Source: https://www.psx-place.com/resources/popsloader.1396/
SET "TITLE" "[PS1] POPSLoader"
SET "VERSION" "1.2.1"
SET "AUTHOR" "https://israpps.github.io/"
SET "DESC" "POPSloader is a GUI for POPSTARTER launcher which lets you play your PS1 games in .VCD format from HDD or USB."
SET "ELF" "POPSLOADER.ELF"
SET "SAS" "PS1_POPSLOADER"
# Comment out 1 of the 2 lines below. If app is in non-mc:/$SAS$ comment out the first, if in non-mc:/APPS/$SAS$ comment out the second
# SET "SAS_NON_MC" "$SAS$"
SET "SAS_NON_MC" "APPS/$SAS$"
#
# If an app does not boot, then one of these compatibility options may need to be set to 0, 1, 2 or 3
# 0= No compatibility options, 1= SHUTDOWN "MM", 2= SET "BM.AUTOLOAD_FSD_EN" "0", 3= CC SLEEP
SET "COMP_MODE_MC" "1"
SET "COMP_MODE_MMCE" "1"
SET "COMP_MODE_USB" "1"
SET "COMP_MODE_HDD_APA" "1"
SET "COMP_MODE_DFFS" "1"
#

# Do not change these 2 lines!
GOTO "$ARG1$"
RETURN -1

# Used for Autoboot Labels
:LABEL_NAME
    ADDWIDGET "LABEL" "$ARG2$$TITLE$ v$VERSION$"
    EXIT 0

:QUERY
    IF MATCHES "$ARG3$" "APP_CONFIG"
        EXIT 0
    ELSE
        ADDWIDGET "CALL" "$TITLE$" "$BM.TXT_VERSION$: $VERSION$ $BM.TXT_AUTHOR$: $AUTHOR$ $BM.TXT_DESC$: $DESC$" $ARG2$ "$ARG0$" "$ARG3$" "$ARG4$" "$ARG5$" "$TITLE$" "$PWD$" "$SAS$" "$SAS_NON_MC$"
    ENDIF
    EXIT 0

:INSTALL
        IF MATCHES "mc?" "$ARG2$"
            GOTO "INSTALL_TO_MC"
        ELSEIF NOT MATCHES "mc?" "$ARG2$"
            GOTO "INSTALL_TO_NONMC"
        ENDIF

:INSTALL_TO_MC
    IF FAIL COPY "$PWD$" "$ARG2$:/$SAS$"
        ECHO "Failed installing $TITLE$"
        MESSAGE "Failed installing $TITLE$"
        RRM "$ARG2$:/$SAS$"
        RETURN -1
    ENDIF
    EXIT 0

:INSTALL_TO_NONMC
    IF FAIL COPY "$PWD$" "$ARG2$:/$SAS_NON_MC$"
        ECHO "Failed installing $TITLE$"
        MESSAGE "Failed installing $TITLE$"
        RRM "$ARG2$:/$SAS_NON_MC$"
        RETURN -1
    ENDIF
    EXIT 0

:REMOVE
    IF FAIL RRM "$PWD$"
        IF FAIL RRM "$PWD$"
            IF FAIL RRM "$PWD$"
                MESSAGE "Failed removing $TITLE$!"
                RETURN -1
            ENDIF
        ENDIF
    ENDIF
    EXIT 0

:RUN
    IF MATCHES "mc?:/*" "$PWD$"
        GOTO "RUN_MC"
    ELSEIF MATCHES "mmce?:/*" "$PWD$"
        GOTO "RUN_MMCE"
    ELSEIF MATCHES "mass:/*" "$PWD$"
        GOTO "RUN_USB"
    ELSEIF MATCHES "pfs0:/*" "$PWD$"
        GOTO "RUN_HDD_APA"
    ELSEIF MATCHES "dffs:/*" "$PWD$"
        GOTO "RUN_DFFS"
    ENDIF

:RUN_MC
    IF EQU "$COMP_MODE_MC$" "1"
        SHUTDOWN "MM"
    ELSEIF EQU "$COMP_MODE_MC$" "2"
        SET "BM.AUTOLOAD_FSD_EN" "0"
    ELSEIF EQU "$COMP_MODE_MC$" "3"
        SETBIOS "OFF"
        SHUTDOWN "ALL"
    ENDIF
    GOTO "RUN_COMP_MODE"

:RUN_MMCE
    IF EQU "$COMP_MODE_MMCE$" "1"
        SHUTDOWN "MM"
    ELSEIF EQU "$COMP_MODE_MMCE$" "2"
        SET "BM.AUTOLOAD_FSD_EN" "0"
    ELSEIF EQU "$COMP_MODE_MMCE$" "3"
        SETBIOS "OFF"
        SHUTDOWN "ALL"
    ENDIF
    GOTO "RUN_COMP_MODE"

:RUN_USB
    IF EQU "$COMP_MODE_USB$" "1"
        SHUTDOWN "MM"
    ELSEIF EQU "$COMP_MODE_USB$" "2"
        SET "BM.AUTOLOAD_FSD_EN" "0"
    ELSEIF EQU "$COMP_MODE_USB$" "3"
        SETBIOS "OFF"
        SHUTDOWN "ALL"
    ENDIF
    GOTO "RUN_COMP_MODE"

:RUN_HDD_APA
    IF EQU "$COMP_MODE_HDD_APA$" "1"
        SHUTDOWN "MM"
    ELSEIF EQU "$COMP_MODE_HDD_APA$" "2"
        SET "BM.AUTOLOAD_FSD_EN" "0"
    ELSEIF EQU "$COMP_MODE_HDD_APA$" "3"
        SETBIOS "OFF"
        SHUTDOWN "ALL"
    ENDIF
    GOTO "RUN_COMP_MODE"

:RUN_DFFS
    IF EQU "$COMP_MODE_DFFS$" "1"
        SHUTDOWN "MM"
    ELSEIF EQU "$COMP_MODE_DFFS$" "2"
        SET "BM.AUTOLOAD_FSD_EN" "0"
    ELSEIF EQU "$COMP_MODE_DFFS$" "3"
        SETBIOS "OFF"
        SHUTDOWN "ALL"
    ENDIF
    GOTO "RUN_COMP_MODE"

:RUN_COMP_MODE
    LOADEXEC "PBAT" "$BM.SCRIPTS$/LOADEXEC.PBT" "$PWD$/$ELF$"
    EXIT 0
