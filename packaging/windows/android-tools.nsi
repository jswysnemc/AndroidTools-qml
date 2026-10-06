Unicode True

!include "MUI2.nsh"

!ifndef APP_VERSION
  !define APP_VERSION "0.1.0"
!endif
!ifndef STAGE_DIR
  !error "STAGE_DIR is required"
!endif
!ifndef OUT_DIR
  !error "OUT_DIR is required"
!endif
!ifndef LICENSE_FILE
  !error "LICENSE_FILE is required"
!endif

Name "AndroidTools ${APP_VERSION}"
OutFile "${OUT_DIR}/AndroidTools-${APP_VERSION}-windows-x64-setup.exe"
InstallDir "$PROGRAMFILES64\AndroidTools"
InstallDirRegKey HKLM "Software\AndroidTools" "InstallDir"
RequestExecutionLevel admin
SetCompressor /SOLID lzma

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${LICENSE_FILE}"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"

Section "AndroidTools" SecApp
  SetOutPath "$INSTDIR"
  File /r "${STAGE_DIR}\*.*"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "Software\AndroidTools" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\AndroidTools" "DisplayName" "AndroidTools"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\AndroidTools" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\AndroidTools" "Publisher" "mhduiy"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\AndroidTools" "UninstallString" "$\"$INSTDIR\Uninstall.exe$\""
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\AndroidTools" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\AndroidTools" "NoRepair" 1

  CreateDirectory "$SMPROGRAMS\AndroidTools"
  CreateShortcut "$SMPROGRAMS\AndroidTools\AndroidTools.lnk" "$INSTDIR\AndroidTools.exe"
  CreateShortcut "$DESKTOP\AndroidTools.lnk" "$INSTDIR\AndroidTools.exe"
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\AndroidTools.lnk"
  Delete "$SMPROGRAMS\AndroidTools\AndroidTools.lnk"
  RMDir "$SMPROGRAMS\AndroidTools"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\AndroidTools"
  DeleteRegKey HKLM "Software\AndroidTools"
SectionEnd
