Add-Type -AssemblyName PresentationFramework

function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-RunAsAdmin {
    if (-not (Test-IsAdmin)) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = '-ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
        $psi.Verb = 'runas'
        try {
            [System.Diagnostics.Process]::Start($psi) | Out-Null
        }
        catch {
            [System.Windows.MessageBox]::Show('Serve avviare il pannello come amministratore.', 'TedeTweak') | Out-Null
        }
        exit
    }
}

function Set-RegDword {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Set-RegString {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Value
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -PropertyType String -Value $Value -Force | Out-Null
}

function Disable-ServiceSafe {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        return 'SKIP servizio non trovato: ' + $Name
    }

    try {
        if ($svc.Status -ne 'Stopped') {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        }
        Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        return 'Servizio disabilitato: ' + $Name
    }
    catch {
        return 'SKIP servizio ' + $Name + ': ' + $_.Exception.Message
    }
}

function Disable-ScheduledTaskSafe {
    param(
        [string]$TaskPath,
        [string]$TaskName
    )
    try {
        $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop
        Disable-ScheduledTask -InputObject $task | Out-Null
        return 'Task disabilitato: ' + $TaskPath + $TaskName
    }
    catch {
        return 'SKIP task: ' + $TaskPath + $TaskName
    }
}

function Stop-ProcessSafe {
    param([string]$Name)
    $list = Get-Process -Name $Name -ErrorAction SilentlyContinue
    if (-not $list) {
        return 'SKIP processo non attivo: ' + $Name
    }

    try {
        $list | Stop-Process -Force -ErrorAction SilentlyContinue
        return 'Processo fermato: ' + $Name
    }
    catch {
        return 'SKIP processo ' + $Name + ': ' + $_.Exception.Message
    }
}

$script:TedeWorkspaceInitialized = $false
$script:TedeDataRoot = $null
$script:TedeBackupRoot = $null
$script:TedeLogRoot = $null
$script:TedeCurrentLog = $null
$script:TedeLatestBackup = $null

function Initialize-TedeWorkspace {
    if ($script:TedeWorkspaceInitialized) { return }

    $basePath = Split-Path -Parent $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($basePath)) {
        $basePath = (Get-Location).Path
    }

    $script:TedeDataRoot = Join-Path $basePath 'TedeTweakData'
    $script:TedeBackupRoot = Join-Path $script:TedeDataRoot 'Backups'
    $script:TedeLogRoot = Join-Path $script:TedeDataRoot 'Logs'

    foreach ($dir in @($script:TedeDataRoot, $script:TedeBackupRoot, $script:TedeLogRoot)) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }

    $script:TedeCurrentLog = Join-Path $script:TedeLogRoot ('tede_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
    $script:TedeWorkspaceInitialized = $true
}

function Write-TedeLog {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )

    Initialize-TedeWorkspace
    $line = ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] [' + $Level + '] ' + $Message)
    Add-Content -Path $script:TedeCurrentLog -Value $line -Encoding UTF8
}

function Export-RegistryBackupSafe {
    param(
        [string]$RegistryPath,
        [string]$OutputFile
    )

    try {
        & reg.exe export $RegistryPath $OutputFile /y | Out-Null
        if (Test-Path $OutputFile) {
            return 'Backup registry creato: ' + [System.IO.Path]::GetFileName($OutputFile)
        }
        return 'SKIP backup registry: ' + $RegistryPath
    }
    catch {
        return 'SKIP backup registry ' + $RegistryPath + ': ' + $_.Exception.Message
    }
}

function New-TedeSafetyBackup {
    Initialize-TedeWorkspace

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir = Join-Path $script:TedeBackupRoot $stamp
    New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    $script:TedeLatestBackup = $backupDir

    $items = New-Object System.Collections.Generic.List[string]
    $items.Add('Cartella backup: ' + $backupDir)

    foreach ($pair in @(
        @{ Path = 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management'; File = 'memory-management.reg' },
        @{ Path = 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\PriorityControl'; File = 'priority-control.reg' },
        @{ Path = 'HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile'; File = 'multimedia-systemprofile.reg' },
        @{ Path = 'HKLM\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters'; File = 'tcpip-parameters.reg' },
        @{ Path = 'HKLM\\SYSTEM\\CurrentControlSet\\Services\\Ndu'; File = 'ndu.reg' },
        @{ Path = 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Power'; File = 'session-power.reg' },
        @{ Path = 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Power'; File = 'power.reg' },
        @{ Path = 'HKCU\\Control Panel\\Mouse'; File = 'hkcu-mouse.reg' },
        @{ Path = 'HKCU\\Control Panel\\Keyboard'; File = 'hkcu-keyboard.reg' },
        @{ Path = 'HKCU\\Software\\Microsoft\\GameBar'; File = 'hkcu-gamebar.reg' }
    )) {
        $items.Add((Export-RegistryBackupSafe -RegistryPath $pair.Path -OutputFile (Join-Path $backupDir $pair.File)))
    }

    try {
        Checkpoint-Computer -Description ('TedeTweak_' + $stamp) -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop | Out-Null
        $items.Add('Restore point creato: TedeTweak_' + $stamp)
    }
    catch {
        $items.Add('SKIP restore point: ' + $_.Exception.Message)
    }

    Write-TedeLog ('Backup creato in ' + $backupDir)
    return $items
}

function Restore-LatestTedeBackup {
    Initialize-TedeWorkspace

    if (-not (Test-Path $script:TedeBackupRoot)) {
        return @('SKIP nessuna cartella backup disponibile')
    }

    $latest = Get-ChildItem -Path $script:TedeBackupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $latest) {
        return @('SKIP nessun backup trovato')
    }

    $result = New-Object System.Collections.Generic.List[string]
    $result.Add('Ripristino da: ' + $latest.FullName)
    foreach ($file in Get-ChildItem -Path $latest.FullName -Filter '*.reg' -ErrorAction SilentlyContinue) {
        try {
            & reg.exe import $file.FullName | Out-Null
            $result.Add('Importato: ' + $file.Name)
        }
        catch {
            $result.Add('SKIP import ' + $file.Name + ': ' + $_.Exception.Message)
        }
    }

    Write-TedeLog ('Ripristino eseguito da ' + $latest.FullName)
    return $result
}

function Open-TedePath {
    param([string]$Path)
    try {
        if (Test-Path $Path) {
            Start-Process explorer.exe $Path | Out-Null
        }
    }
    catch { }
}

function Apply-ServicesBase {
    $applied = @()
    $services = @(
        'SysMain',
        'WSearch',
        'DiagTrack',
        'dmwappushservice',
        'MapsBroker',
        'Fax',
        'RemoteRegistry',
        'WMPNetworkSvc',
        'RetailDemo',
        'WerSvc',
        'BthAvctpSvc',
        'DusmSvc',
        'TrkWks',
        'WbioSrvc',
        'AJRouter',
        'XblAuthManager',
        'XblGameSave',
        'XboxGipSvc',
        'XboxNetApiSvc'
    )

    foreach ($service in $services) {
        $applied += Disable-ServiceSafe -Name $service
    }

    $applied += Disable-ScheduledTaskSafe -TaskPath '\Microsoft\Windows\Application Experience\' -TaskName 'Microsoft Compatibility Appraiser'
    $applied += Disable-ScheduledTaskSafe -TaskPath '\Microsoft\Windows\Customer Experience Improvement Program\' -TaskName 'Consolidator'
    $applied += Disable-ScheduledTaskSafe -TaskPath '\Microsoft\Windows\Customer Experience Improvement Program\' -TaskName 'UsbCeip'

    return $applied
}

function Apply-MemoryLite {
    $applied = @()

    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'DisablePagingExecutive' -Value 1
    $applied += 'DisablePagingExecutive = 1'

    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'LargeSystemCache' -Value 0
    $applied += 'LargeSystemCache = 0'

    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'ClearPageFileAtShutdown' -Value 0
    $applied += 'ClearPageFileAtShutdown = 0'

    return $applied
}

function Apply-MemoryAggressive {
    $applied = @()
    $applied += Apply-MemoryLite

    try {
        Disable-MMAgent -mc -ErrorAction Stop | Out-Null
        $applied += 'MemoryCompression disabilitata'
    }
    catch {
        try {
            Disable-MMAgent -MemoryCompression -ErrorAction Stop | Out-Null
            $applied += 'MemoryCompression disabilitata'
        }
        catch {
            $applied += 'SKIP MemoryCompression: ' + $_.Exception.Message
        }
    }

    return $applied
}

function Remove-AppxPackageSafe {
    param(
        [string]$PackagePattern,
        [bool]$RemoveForUsers = $true,
        [bool]$RemoveProvisioned = $true
    )
    $result = @()

    if ($RemoveForUsers) {
        try {
            $packages = Get-AppxPackage -AllUsers -Name $PackagePattern -ErrorAction SilentlyContinue
            if ($packages) {
                foreach ($pkg in $packages) {
                    try {
                        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                        $result += 'App rimossa utenti: ' + $pkg.Name
                    }
                    catch {
                        $result += 'SKIP remove utenti: ' + $pkg.Name
                    }
                }
            }
            else {
                $result += 'SKIP app utenti non trovata: ' + $PackagePattern
            }
        }
        catch {
            $result += 'SKIP query utenti: ' + $PackagePattern
        }
    }
    else {
        $result += 'SKIP utenti per scelta: ' + $PackagePattern
    }

    if ($RemoveProvisioned) {
        try {
            $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $PackagePattern }
            if ($prov) {
                foreach ($pkg in $prov) {
                    try {
                        Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction SilentlyContinue | Out-Null
                        $result += 'Provisioned rimossa: ' + $pkg.DisplayName
                    }
                    catch {
                        $result += 'SKIP provisioned: ' + $pkg.DisplayName
                    }
                }
            }
            else {
                $result += 'SKIP provisioned non trovata: ' + $PackagePattern
            }
        }
        catch {
            $result += 'SKIP query provisioned: ' + $PackagePattern
        }
    }
    else {
        $result += 'SKIP provisioning per scelta: ' + $PackagePattern
    }

    return $result
}

function Get-DebloatMap {
    $map = [ordered]@{}
    $map['Clipchamp'] = 'Clipchamp.Clipchamp'
    $map['Bing News'] = 'Microsoft.BingNews'
    $map['Get Help'] = 'Microsoft.GetHelp'
    $map['Get Started'] = 'Microsoft.Getstarted'
    $map['Office Hub'] = 'Microsoft.MicrosoftOfficeHub'
    $map['Solitaire'] = 'Microsoft.MicrosoftSolitaireCollection'
    $map['People'] = 'Microsoft.People'
    $map['Skype'] = 'Microsoft.SkypeApp'
    $map['Teams Consumer'] = 'MicrosoftTeams'
    $map['Xbox TCUI'] = 'Microsoft.Xbox.TCUI'
    $map['Xbox App'] = 'Microsoft.XboxApp'
    $map['Xbox Game Overlay'] = 'Microsoft.XboxGameOverlay'
    $map['Xbox Gaming Overlay'] = 'Microsoft.XboxGamingOverlay'
    $map['Xbox Identity Provider'] = 'Microsoft.XboxIdentityProvider'
    $map['Xbox Speech To Text'] = 'Microsoft.XboxSpeechToTextOverlay'
    $map['Phone Link'] = 'Microsoft.YourPhone'
    $map['Groove Music'] = 'Microsoft.ZuneMusic'
    $map['Movies and TV'] = 'Microsoft.ZuneVideo'
    $map['To Do'] = 'Microsoft.Todos'
    $map['Family'] = 'MicrosoftCorporationII.MicrosoftFamily'
    $map['Quick Assist'] = 'MicrosoftCorporationII.QuickAssist'
    $map['Dev Home'] = 'Microsoft.Windows.DevHome'
    $map['Feedback Hub'] = 'Microsoft.WindowsFeedbackHub'
    $map['Maps'] = 'Microsoft.WindowsMaps'
    $map['Camera'] = 'Microsoft.WindowsCamera'
    $map['Sound Recorder'] = 'Microsoft.WindowsSoundRecorder'
    $map['Alarms'] = 'Microsoft.WindowsAlarms'
    $map['Mail and Calendar'] = 'microsoft.windowscommunicationsapps'
    return $map
}

function Apply-DebloatSelection {
    param(
        [string[]]$Items,
        [bool]$RemoveForUsers = $true,
        [bool]$RemoveProvisioned = $true
    )

    $applied = @()
    Set-RegDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures' -Value 1
    $applied += 'DisableWindowsConsumerFeatures = 1'

    Set-RegDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SilentInstalledAppsEnabled' -Value 0
    $applied += 'SilentInstalledAppsEnabled = 0'

    Set-RegDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SubscribedContent-338388Enabled' -Value 0
    $applied += 'SubscribedContent-338388Enabled = 0'

    Set-RegDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SubscribedContent-338389Enabled' -Value 0
    $applied += 'SubscribedContent-338389Enabled = 0'

    $map = Get-DebloatMap
    foreach ($item in $Items) {
        if ($map.Contains($item)) {
            $applied += Remove-AppxPackageSafe -PackagePattern $map[$item] -RemoveForUsers $RemoveForUsers -RemoveProvisioned $RemoveProvisioned
        }
        else {
            $applied += 'SKIP voce debloat sconosciuta: ' + $item
        }
    }

    return $applied
}

function Apply-DebloatSafe {
    $safeItems = @(
        'Clipchamp',
        'Bing News',
        'Get Help',
        'Get Started',
        'Office Hub',
        'Solitaire',
        'People',
        'Skype',
        'Teams Consumer',
        'Xbox TCUI',
        'Xbox App',
        'Xbox Game Overlay',
        'Xbox Gaming Overlay',
        'Xbox Identity Provider',
        'Xbox Speech To Text',
        'Phone Link',
        'Groove Music',
        'Movies and TV'
    )
    return Apply-DebloatSelection -Items $safeItems -RemoveForUsers $true -RemoveProvisioned $true
}

function Apply-DebloatAggressive {
    $aggressiveItems = @(
        'Clipchamp',
        'Bing News',
        'Get Help',
        'Get Started',
        'Office Hub',
        'Solitaire',
        'People',
        'Skype',
        'Teams Consumer',
        'Xbox TCUI',
        'Xbox App',
        'Xbox Game Overlay',
        'Xbox Gaming Overlay',
        'Xbox Identity Provider',
        'Xbox Speech To Text',
        'Phone Link',
        'Groove Music',
        'Movies and TV',
        'To Do',
        'Family',
        'Quick Assist',
        'Dev Home',
        'Feedback Hub',
        'Maps',
        'Camera',
        'Sound Recorder',
        'Alarms',
        'Mail and Calendar'
    )
    return Apply-DebloatSelection -Items $aggressiveItems -RemoveForUsers $true -RemoveProvisioned $true
}

function Apply-InputTweaks {
    $applied = @()

    Set-RegString -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -Value '0'
    $applied += 'MouseSpeed = 0'

    Set-RegString -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0'
    $applied += 'MouseThreshold1 = 0'

    Set-RegString -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0'
    $applied += 'MouseThreshold2 = 0'

    Set-RegString -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseHoverTime' -Value '0'
    $applied += 'MouseHoverTime = 0'

    Set-RegString -Path 'HKCU:\Control Panel\Keyboard' -Name 'KeyboardSpeed' -Value '31'
    $applied += 'KeyboardSpeed = 31'

    Set-RegString -Path 'HKCU:\Control Panel\Keyboard' -Name 'KeyboardDelay' -Value '0'
    $applied += 'KeyboardDelay = 0'

    Set-RegString -Path 'HKCU:\Control Panel\Accessibility\StickyKeys' -Name 'Flags' -Value '506'
    $applied += 'StickyKeys Flags = 506'

    Set-RegString -Path 'HKCU:\Control Panel\Accessibility\ToggleKeys' -Name 'Flags' -Value '58'
    $applied += 'ToggleKeys Flags = 58'

    Set-RegString -Path 'HKCU:\Control Panel\Accessibility\Keyboard Response' -Name 'Flags' -Value '122'
    $applied += 'Keyboard Response Flags = 122'

    Set-RegString -Path 'HKCU:\Control Panel\Accessibility\Keyboard Response' -Name 'DelayBeforeAcceptance' -Value '0'
    $applied += 'DelayBeforeAcceptance = 0'

    Set-RegString -Path 'HKCU:\Control Panel\Accessibility\Keyboard Response' -Name 'AutoRepeatDelay' -Value '0'
    $applied += 'AutoRepeatDelay = 0'

    Set-RegString -Path 'HKCU:\Control Panel\Accessibility\Keyboard Response' -Name 'AutoRepeatRate' -Value '0'
    $applied += 'AutoRepeatRate = 0'

    return $applied
}

function Apply-UsbLowLatency {
    $applied = @()

    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\USB' -Name 'DisableSelectiveSuspend' -Value 1
    $applied += 'DisableSelectiveSuspend = 1'

    $count = 0
    try {
        $devices = Get-PnpDevice -Class USB -PresentOnly -ErrorAction SilentlyContinue
        foreach ($device in $devices) {
            $path = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $device.InstanceId + '\Device Parameters'
            if (Test-Path $path) {
                New-ItemProperty -Path $path -Name 'EnhancedPowerManagementEnabled' -PropertyType DWord -Value 0 -Force | Out-Null
                $count++
            }
        }
        $applied += 'EnhancedPowerManagementEnabled = 0 su ' + $count + ' device USB'
    }
    catch {
        $applied += 'SKIP USB device tuning: ' + $_.Exception.Message
    }

    return $applied
}

function Apply-PowerAdvanced {
    $applied = @()

    try {
        $dup = (powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-String)
        if ($dup -match '([0-9a-fA-F\-]{36})') {
            powercfg -setactive $matches[1] 2>$null | Out-Null
            $applied += 'Ultimate Performance attivato: ' + $matches[1]
        }
        else {
            $applied += 'Ultimate Performance duplicato o gia disponibile'
        }
    }
    catch {
        $applied += 'SKIP Ultimate Performance: ' + $_.Exception.Message
    }

    try { powercfg -hibernate off 2>$null | Out-Null; $applied += 'Hibernate = off' } catch { $applied += 'SKIP hibernate off' }
    try { powercfg -change monitor-timeout-ac 0 2>$null | Out-Null; $applied += 'Monitor timeout AC = 0' } catch { $applied += 'SKIP monitor timeout AC' }
    try { powercfg -change monitor-timeout-dc 0 2>$null | Out-Null; $applied += 'Monitor timeout DC = 0' } catch { $applied += 'SKIP monitor timeout DC' }
    try { powercfg -change disk-timeout-ac 0 2>$null | Out-Null; $applied += 'Disk timeout AC = 0' } catch { $applied += 'SKIP disk timeout AC' }
    try { powercfg -change disk-timeout-dc 0 2>$null | Out-Null; $applied += 'Disk timeout DC = 0' } catch { $applied += 'SKIP disk timeout DC' }

    try { powercfg -setacvalueindex SCHEME_CURRENT SUBPROCESSOR PROCTHROTTLEMIN 100 2>$null | Out-Null; $applied += 'CPU min AC = 100' } catch { $applied += 'SKIP CPU min AC' }
    try { powercfg -setdcvalueindex SCHEME_CURRENT SUBPROCESSOR PROCTHROTTLEMIN 100 2>$null | Out-Null; $applied += 'CPU min DC = 100' } catch { $applied += 'SKIP CPU min DC' }
    try { powercfg -setacvalueindex SCHEME_CURRENT SUBPROCESSOR PROCTHROTTLEMAX 100 2>$null | Out-Null; $applied += 'CPU max AC = 100' } catch { $applied += 'SKIP CPU max AC' }
    try { powercfg -setdcvalueindex SCHEME_CURRENT SUBPROCESSOR PROCTHROTTLEMAX 100 2>$null | Out-Null; $applied += 'CPU max DC = 100' } catch { $applied += 'SKIP CPU max DC' }
    try { powercfg -setacvalueindex SCHEME_CURRENT SUBPROCESSOR CPMINCORES 100 2>$null | Out-Null; $applied += 'CPU min cores AC = 100' } catch { $applied += 'SKIP CPU min cores AC' }
    try { powercfg -setdcvalueindex SCHEME_CURRENT SUBPROCESSOR CPMINCORES 100 2>$null | Out-Null; $applied += 'CPU min cores DC = 100' } catch { $applied += 'SKIP CPU min cores DC' }
    try { powercfg -setacvalueindex SCHEME_CURRENT SUBPROCESSOR CPMAXCORES 100 2>$null | Out-Null; $applied += 'CPU max cores AC = 100' } catch { $applied += 'SKIP CPU max cores AC' }
    try { powercfg -setdcvalueindex SCHEME_CURRENT SUBPROCESSOR CPMAXCORES 100 2>$null | Out-Null; $applied += 'CPU max cores DC = 100' } catch { $applied += 'SKIP CPU max cores DC' }
    try { powercfg -setacvalueindex SCHEME_CURRENT SUBPROCESSOR IDLEDISABLE 1 2>$null | Out-Null; $applied += 'CPU idle AC = disabled' } catch { $applied += 'SKIP CPU idle AC' }
    try { powercfg -setdcvalueindex SCHEME_CURRENT SUBPROCESSOR IDLEDISABLE 1 2>$null | Out-Null; $applied += 'CPU idle DC = disabled' } catch { $applied += 'SKIP CPU idle DC' }
    try { powercfg -setacvalueindex SCHEME_CURRENT SUBUSB USBSELECTSUSPEND 0 2>$null | Out-Null; $applied += 'USB selective suspend AC = 0' } catch { $applied += 'SKIP USB selective suspend AC' }
    try { powercfg -setdcvalueindex SCHEME_CURRENT SUBUSB USBSELECTSUSPEND 0 2>$null | Out-Null; $applied += 'USB selective suspend DC = 0' } catch { $applied += 'SKIP USB selective suspend DC' }
    try { powercfg -setacvalueindex SCHEME_CURRENT SUBPCIEXPRESS ASPM 0 2>$null | Out-Null; $applied += 'ASPM AC = 0' } catch { $applied += 'SKIP ASPM AC' }
    try { powercfg -setdcvalueindex SCHEME_CURRENT SUBPCIEXPRESS ASPM 0 2>$null | Out-Null; $applied += 'ASPM DC = 0' } catch { $applied += 'SKIP ASPM DC' }
    try { powercfg -setactive SCHEME_CURRENT 2>$null | Out-Null; $applied += 'SCHEME_CURRENT riapplicato' } catch { $applied += 'SKIP setactive current' }

    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Value 0
    $applied += 'HiberbootEnabled = 0'

    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -Name 'PowerThrottlingOff' -Value 1
    $applied += 'PowerThrottlingOff = 1'

    return $applied
}

function Apply-SchedulerMMCSS {
    $applied = @()

    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 38
    $applied += 'Win32PrioritySeparation = 38'

    if (-not (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile')) {
        New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Force | Out-Null
    }
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex' -PropertyType DWord -Value 0xFFFFFFFF -Force | Out-Null
    $applied += 'NetworkThrottlingIndex = 0xffffffff'

    Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'SystemResponsiveness' -Value 0
    $applied += 'SystemResponsiveness = 0'

    Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'GPU Priority' -Value 8
    $applied += 'Games GPU Priority = 8'

    Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'Priority' -Value 6
    $applied += 'Games Priority = 6'

    Set-RegString -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'Scheduling Category' -Value 'High'
    $applied += 'Games Scheduling Category = High'

    Set-RegString -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'SFIO Priority' -Value 'High'
    $applied += 'Games SFIO Priority = High'

    Set-RegString -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'Background Only' -Value 'False'
    $applied += 'Games Background Only = False'

    Set-RegDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched' -Name 'NonBestEffortLimit' -Value 0
    $applied += 'NonBestEffortLimit = 0'

    return $applied
}

function Apply-BackgroundCleanupSafe {
    $applied = @()

    Set-RegDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarDa' -Value 0
    $applied += 'TaskbarDa = 0'

    Set-RegDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Value 0
    $applied += 'SearchboxTaskbarMode = 0'

    Set-RegDword -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications' -Name 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' -Value 0
    $applied += 'NOC_GLOBAL_SETTING_TOASTS_ENABLED = 0'

    $processes = @(
        'Widgets',
        'WidgetService',
        'GameBar',
        'GameBarFTServer',
        'XboxPcAppFT'
    )

    foreach ($name in $processes) {
        $applied += Stop-ProcessSafe -Name $name
    }

    return $applied
}

function Apply-GamingCommon {
    $applied = @()

    Set-RegDword -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0
    $applied += 'GameDVR_Enabled = 0'

    Set-RegDword -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_FSEBehavior' -Value 2
    $applied += 'GameDVR_FSEBehavior = 2'

    Set-RegDword -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_DXGIHonorFSEWindowsCompatible' -Value 1
    $applied += 'GameDVR_DXGIHonorFSEWindowsCompatible = 1'

    Set-RegDword -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_HonorUserFSEBehaviorMode' -Value 1
    $applied += 'GameDVR_HonorUserFSEBehaviorMode = 1'

    Set-RegDword -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value 0
    $applied += 'AppCaptureEnabled = 0'

    Set-RegDword -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1
    $applied += 'AutoGameModeEnabled = 1'

    Set-RegDword -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AllowAutoGameMode' -Value 1
    $applied += 'AllowAutoGameMode = 1'

    Set-RegDword -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'ShowStartupPanel' -Value 0
    $applied += 'ShowStartupPanel = 0'

    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Value 2
    $applied += 'HwSchMode = 2'

    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'TdrDelay' -Value 10
    $applied += 'TdrDelay = 10'

    return $applied
}

function Clear-DirectoryContentSafe {
    param([string]$Path)
    try {
        if (Test-Path $Path) {
            Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            return 'Pulita cartella: ' + $Path
        }
        return 'SKIP cartella non trovata: ' + $Path
    }
    catch {
        return 'SKIP pulizia ' + $Path + ': ' + $_.Exception.Message
    }
}

function Apply-StorageAdvanced {
    $applied = @()

    try { fsutil behavior set DisableDeleteNotify 0 | Out-Null; $applied += 'DisableDeleteNotify = 0' } catch { $applied += 'SKIP DisableDeleteNotify' }
    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'NtfsDisableLastAccessUpdate' -Value 1
    $applied += 'NtfsDisableLastAccessUpdate = 1'
    Set-RegString -Path 'HKLM:\SOFTWARE\Microsoft\Dfrg\BootOptimizeFunction' -Name 'Enable' -Value 'Y'
    $applied += 'BootOptimizeFunction Enable = Y'

    try {
        $vols = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
        foreach ($vol in $vols) {
            try {
                Optimize-Volume -DriveLetter $vol.DriveLetter -ErrorAction SilentlyContinue | Out-Null
                $applied += 'Optimize-Volume su ' + $vol.DriveLetter
            }
            catch {
                $applied += 'SKIP Optimize-Volume su ' + $vol.DriveLetter
            }
        }
    }
    catch {
        $applied += 'SKIP query volumi: ' + $_.Exception.Message
    }

    return $applied
}

function Apply-DisplayPipeline {
    $applied = @()
    Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' -Name 'OverlayTestMode' -Value 5
    $applied += 'OverlayTestMode = 5'
    return $applied
}

function Apply-CacheCleanup {
    $applied = @()
    $paths = @(
        $env:TEMP,
        "$env:WINDIR\Temp",
        "$env:LOCALAPPDATA\D3DSCache",
        "$env:LOCALAPPDATA\NVIDIA\DXCache",
        "$env:LOCALAPPDATA\AMD\DxCache",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    )

    foreach ($p in $paths) {
        $applied += Clear-DirectoryContentSafe -Path $p
    }

    try { ipconfig /flushdns | Out-Null; $applied += 'DNS cache flush' } catch { $applied += 'SKIP DNS flush' }
    return $applied
}

function Apply-ProcessCleanupSafePro {
    $applied = @()
    $targets = @(
        'Widgets',
        'WidgetService',
        'GameBar',
        'GameBarFTServer',
        'PhoneExperienceHost',
        'YourPhone',
        'MicrosoftEdgeWebView2',
        'TextInputHost',
        'LockApp'
    )

    foreach ($proc in $targets) {
        $applied += Stop-ProcessSafe -Name $proc
    }

    return $applied
}

function Apply-NetworkCommon {
    $applied = @()

    try { netsh interface tcp set global autotuninglevel=normal | Out-Null; $applied += 'autotuninglevel = normal' } catch { $applied += 'SKIP autotuninglevel' }
    try { netsh interface tcp set global rss=enabled | Out-Null; $applied += 'rss = enabled' } catch { $applied += 'SKIP rss' }
    try { netsh interface tcp set global rsc=disabled | Out-Null; $applied += 'rsc = disabled' } catch { $applied += 'SKIP rsc' }
    try { netsh interface tcp set global ecncapability=disabled | Out-Null; $applied += 'ecncapability = disabled' } catch { $applied += 'SKIP ecncapability' }
    try { netsh interface tcp set global timestamps=disabled | Out-Null; $applied += 'timestamps = disabled' } catch { $applied += 'SKIP timestamps' }

    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Ndu' -Name 'Start' -Value 4
    $applied += 'Ndu Start = 4'

    try {
        $ifaces = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' -ErrorAction SilentlyContinue
        $count = 0
        foreach ($iface in $ifaces) {
            New-ItemProperty -Path $iface.PSPath -Name 'TcpAckFrequency' -PropertyType DWord -Value 1 -Force | Out-Null
            New-ItemProperty -Path $iface.PSPath -Name 'TCPNoDelay' -PropertyType DWord -Value 1 -Force | Out-Null
            New-ItemProperty -Path $iface.PSPath -Name 'TcpDelAckTicks' -PropertyType DWord -Value 0 -Force | Out-Null
            $count++
        }
        $applied += 'TCP low latency su interfacce: ' + $count
    }
    catch {
        $applied += 'SKIP TCP interface tuning: ' + $_.Exception.Message
    }

    return $applied
}

function Apply-NetworkAdapterMode {
    param([string]$Mode)
    $applied = @()

    try {
        if ($Mode -eq 'Wi-Fi') {
            $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN|802.11' } | Select-Object -First 1
            if ($null -eq $adapter) {
                return @('SKIP nessun Wi-Fi attivo')
            }

            netsh interface ip set dns name="$($adapter.Name)" static 1.1.1.1 primary | Out-Null
            netsh interface ip add dns name="$($adapter.Name)" 1.0.0.1 index=2 | Out-Null
            $applied += 'DNS Cloudflare su Wi-Fi: ' + $adapter.Name

            try { Set-NetAdapterPowerManagement -Name $adapter.Name -AllowComputerToTurnOffDevice Disabled -ErrorAction SilentlyContinue; $applied += 'Power management off: ' + $adapter.Name } catch { $applied += 'SKIP power management Wi-Fi' }
            $pairs = @(
                @('Preferred Band','Prefer 5GHz Band'),
                @('Transmit Power','Highest'),
                @('Roaming Aggressiveness','1. Lowest')
            )
            foreach ($pair in $pairs) {
                try {
                    Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $pair[0] -DisplayValue $pair[1] -NoRestart -ErrorAction SilentlyContinue
                    $applied += $pair[0] + ' = ' + $pair[1]
                }
                catch {
                    $applied += 'SKIP ' + $pair[0]
                }
            }
        }
        else {
            $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface -eq $true -and $_.InterfaceDescription -notmatch 'Wi-?Fi|Wireless|WLAN|802.11' } | Select-Object -First 1
            if ($null -eq $adapter) {
                return @('SKIP nessuna LAN attiva')
            }

            netsh interface ip set dns name="$($adapter.Name)" static 1.1.1.1 primary | Out-Null
            netsh interface ip add dns name="$($adapter.Name)" 1.0.0.1 index=2 | Out-Null
            $applied += 'DNS Cloudflare su LAN: ' + $adapter.Name

            try { Set-NetAdapterPowerManagement -Name $adapter.Name -AllowComputerToTurnOffDevice Disabled -ErrorAction SilentlyContinue; $applied += 'Power management off: ' + $adapter.Name } catch { $applied += 'SKIP power management LAN' }
            $props = @('Interrupt Moderation','Energy-Efficient Ethernet','Green Ethernet','Flow Control')
            foreach ($prop in $props) {
                try {
                    Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $prop -DisplayValue 'Disabled' -NoRestart -ErrorAction SilentlyContinue
                    $applied += $prop + ' = Disabled'
                }
                catch {
                    $applied += 'SKIP ' + $prop
                }
            }
        }
    }
    catch {
        $applied += 'SKIP adapter mode: ' + $_.Exception.Message
    }

    return $applied
}

function Apply-MSIMode {
    $applied = @()
    $count = 0
    try {
        $keys = Get-ChildItem -Path 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -eq 'MessageSignaledInterruptProperties' }
        foreach ($key in $keys) {
            New-ItemProperty -Path $key.PSPath -Name 'MSISupported' -PropertyType DWord -Value 1 -Force | Out-Null
            $count++
        }
        $applied += 'MSISupported = 1 su ' + $count + ' device PCI'
    }
    catch {
        $applied += 'SKIP MSI mode: ' + $_.Exception.Message
    }
    return $applied
}

function Apply-BCDTimerTweaks {
    $applied = @()
    try { bcdedit /set disabledynamictick yes | Out-Null; $applied += 'disabledynamictick = yes' } catch { $applied += 'SKIP disabledynamictick' }
    try { bcdedit /deletevalue useplatformclock | Out-Null; $applied += 'useplatformclock rimosso' } catch { $applied += 'SKIP useplatformclock' }
    try { bcdedit /set useplatformtick yes | Out-Null; $applied += 'useplatformtick = yes' } catch { $applied += 'SKIP useplatformtick' }
    try { bcdedit /set tscsyncpolicy Enhanced | Out-Null; $applied += 'tscsyncpolicy = Enhanced' } catch { $applied += 'SKIP tscsyncpolicy' }
    return $applied
}

function Get-GpuVendor {
    try {
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name } | Select-Object -First 1
        if ($null -eq $gpu) { return 'Unknown' }
        $name = [string]$gpu.Name
        if ($name -match 'AMD|Radeon') { return 'AMD' }
        if ($name -match 'NVIDIA|GeForce') { return 'NVIDIA' }
        if ($name -match 'Intel') { return 'Intel' }
        return $name
    }
    catch {
        return 'Unknown'
    }
}

function Get-ActiveTedeAdapter {
    param([string]$Mode)
    try {
        if ($Mode -eq 'Wi-Fi') {
            return Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN|802.11' } | Select-Object -First 1
        }
        return Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface -eq $true -and $_.InterfaceDescription -notmatch 'Wi-?Fi|Wireless|WLAN|802.11' } | Select-Object -First 1
    }
    catch {
        return $null
    }
}

function Apply-GpuVendorSpecific {
    $applied = @()
    $vendor = Get-GpuVendor
    $applied += 'GPU vendor rilevato: ' + $vendor
    switch ($vendor) {
        'AMD' {
            foreach ($proc in @('RadeonSoftware','AMDRSServ')) { $applied += Stop-ProcessSafe -Name $proc }
            $applied += 'Profilo AMD helper applicato'
        }
        'NVIDIA' {
            foreach ($proc in @('NVIDIA Share','NVIDIA App','nvsphelper64')) { $applied += Stop-ProcessSafe -Name $proc }
            $applied += 'Profilo NVIDIA helper applicato'
        }
        'Intel' {
            foreach ($proc in @('IntelGraphicsSoftware','igfxCUIService')) { $applied += Stop-ProcessSafe -Name $proc }
            $applied += 'Profilo Intel helper applicato'
        }
        default { $applied += 'SKIP vendor-specific: GPU non riconosciuta' }
    }
    return $applied
}

function Apply-GameExeGeneric {
    param([string]$ExePath)
    if ([string]::IsNullOrWhiteSpace($ExePath)) { return @('SKIP game exe generic: percorso non inserito') }
    if (-not (Test-Path $ExePath)) { return @('SKIP game exe generic: file non trovato -> ' + $ExePath) }
    Set-RegString -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -Name $ExePath -Value '~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE'
    return @('AppCompat Flags impostati per: ' + $ExePath, 'Disable Fullscreen Optimizations + High DPI override applicati')
}

function Apply-NicAdvancedTuning {
    param([string]$Mode)
    $applied = @()
    $adapter = Get-ActiveTedeAdapter -Mode $Mode
    if ($null -eq $adapter) { return @('SKIP NIC advanced: nessun adapter ' + $Mode + ' attivo') }
    $applied += 'NIC advanced su: ' + $adapter.Name
    foreach ($prop in @('Interrupt Moderation','Flow Control','Energy-Efficient Ethernet','Green Ethernet','Jumbo Packet','Large Send Offload v2 (IPv4)','Large Send Offload v2 (IPv6)','IPv4 Checksum Offload','TCP Checksum Offload (IPv4)','TCP Checksum Offload (IPv6)','UDP Checksum Offload (IPv4)','UDP Checksum Offload (IPv6)')) {
        try {
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $prop -DisplayValue 'Disabled' -NoRestart -ErrorAction SilentlyContinue
            $applied += $prop + ' = Disabled'
        }
        catch { $applied += 'SKIP ' + $prop }
    }
    foreach ($pair in @(@('Receive Buffers','2048'), @('Transmit Buffers','1024'))) {
        try {
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $pair[0] -DisplayValue $pair[1] -NoRestart -ErrorAction SilentlyContinue
            $applied += $pair[0] + ' = ' + $pair[1]
        }
        catch { $applied += 'SKIP ' + $pair[0] }
    }
    return $applied
}

function Apply-OverlayKiller {
    $applied = @()
    foreach ($proc in @('GameBar','GameBarFTServer','XboxPcAppFT','Overwolf','EpicWebHelper','RadeonSoftware','NVIDIA Share','RTSS')) {
        $applied += Stop-ProcessSafe -Name $proc
    }
    return $applied
}

function Apply-SecurityOptionalProfile {
    $applied = @()
    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'EnableVirtualizationBasedSecurity' -Value 0
    $applied += 'EnableVirtualizationBasedSecurity = 0'
    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled' -Value 0
    $applied += 'HVCI Enabled = 0'
    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LsaCfgFlags' -Value 0
    $applied += 'LsaCfgFlags = 0'
    try { bcdedit /set hypervisorlaunchtype off | Out-Null; $applied += 'hypervisorlaunchtype = off' } catch { $applied += 'SKIP hypervisorlaunchtype' }
    return $applied
}

function Apply-VendorCleanup {
    $applied = @()
    $vendor = Get-GpuVendor
    $applied += 'Vendor cleanup su: ' + $vendor
    switch ($vendor) {
        'AMD' {
            foreach ($proc in @('AMDRSServ','RadeonSoftware')) { $applied += Stop-ProcessSafe -Name $proc }
        }
        'NVIDIA' {
            foreach ($svc in @('NvTelemetryContainer')) { $applied += Disable-ServiceSafe -Name $svc }
            foreach ($proc in @('NVIDIA Share','NVIDIA App','nvsphelper64')) { $applied += Stop-ProcessSafe -Name $proc }
        }
        'Intel' {
            foreach ($proc in @('IntelGraphicsSoftware')) { $applied += Stop-ProcessSafe -Name $proc }
        }
        default { $applied += 'SKIP vendor cleanup: GPU non riconosciuta' }
    }
    return $applied
}

function New-TedeValidationReport {
    Initialize-TedeWorkspace
    $reportRoot = Join-Path $script:TedeDataRoot 'Reports'
    if (-not (Test-Path $reportRoot)) { New-Item -Path $reportRoot -ItemType Directory -Force | Out-Null }
    $file = Join-Path $reportRoot ('validation_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')
    $lines = @()
    $lines += 'TedeTweak Validation Report'
    $lines += ('Date: ' + (Get-Date))
    $lines += (Get-TedeHardwareProfile)
    $lines += ('GPU Vendor: ' + (Get-GpuVendor))
    $lines += ''
    try { $lines += 'Active power scheme:'; $lines += (powercfg /getactivescheme | Out-String).Trim() } catch { $lines += 'SKIP power scheme' }
    $lines += ''
    try { $lines += 'BCD excerpt:'; $lines += (bcdedit /enum | Out-String).Trim() } catch { $lines += 'SKIP bcdedit' }
    $lines += ''
    try { $lines += 'Adapters up:'; $lines += (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Format-Table Name, InterfaceDescription, Status -AutoSize | Out-String).Trim() } catch { $lines += 'SKIP netadapter' }
    Set-Content -Path $file -Value $lines -Encoding UTF8
    return 'Validation report salvato: ' + $file
}

function Apply-FortniteSpecific {
    $applied = @()
    $roots = @('C:\Program Files\Epic Games', 'C:\Program Files (x86)\Epic Games', 'D:\Epic Games', 'E:\Epic Games')
    $found = @()

    foreach ($root in $roots) {
        if (Test-Path $root) {
            $items = Get-ChildItem -Path $root -Filter 'FortniteClient-Win64-Shipping.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 3
            foreach ($item in $items) {
                $found += $item.FullName
            }
        }
    }

    if ($found.Count -eq 0) {
        return @('FortniteClient-Win64-Shipping.exe non trovato')
    }

    $layersPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    foreach ($exe in $found | Select-Object -Unique) {
        Set-RegString -Path $layersPath -Name $exe -Value '~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE'
        $applied += 'Compat layer impostato per ' + $exe
    }

    return $applied
}

Ensure-RunAsAdmin

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TedeTweak Grand Line Console"
        Height="820"
        Width="1240"
        WindowStartupLocation="CenterScreen"
        Background="#07111A"
        Foreground="#F7E7C1"
        FontFamily="Segoe UI">
    <Window.Resources>
        <SolidColorBrush x:Key="BgMain" Color="#07111A"/>
        <SolidColorBrush x:Key="BgPanel" Color="#120E0A"/>
        <SolidColorBrush x:Key="BgPanel2" Color="#1E1510"/>
        <SolidColorBrush x:Key="BgPanel3" Color="#241811"/>
        <SolidColorBrush x:Key="Gold" Color="#D6A84F"/>
        <SolidColorBrush x:Key="GoldSoft" Color="#F4D28C"/>
        <SolidColorBrush x:Key="Parchment" Color="#FFF1CC"/>
        <SolidColorBrush x:Key="TextSoft" Color="#E8D6AE"/>
        <SolidColorBrush x:Key="Muted" Color="#BDAA84"/>
        <SolidColorBrush x:Key="RedCaptain" Color="#8C2F20"/>
        <SolidColorBrush x:Key="RedYonko" Color="#5A1E18"/>
        <SolidColorBrush x:Key="SeaBlue" Color="#12344A"/>
        <SolidColorBrush x:Key="SafeTeal" Color="#0F766E"/>

        <Style TargetType="Border" x:Key="PanelCard">
            <Setter Property="Background" Value="{StaticResource BgPanel2}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Gold}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="10"/>
            <Setter Property="Padding" Value="12"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
        </Style>

        <Style TargetType="Button" x:Key="NavButtonStyle">
            <Setter Property="Height" Value="52"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
            <Setter Property="Background" Value="#20150E"/>
            <Setter Property="Foreground" Value="{StaticResource Parchment}"/>
            <Setter Property="BorderBrush" Value="#8A6735"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>

        <Style TargetType="Button" x:Key="ActionButtonStyle">
            <Setter Property="Height" Value="42"/>
            <Setter Property="Padding" Value="18,8"/>
            <Setter Property="Margin" Value="0,0,10,0"/>
            <Setter Property="Foreground" Value="{StaticResource Parchment}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Gold}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontWeight" Value="Bold"/>
        </Style>

        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{StaticResource TextSoft}"/>
            <Setter Property="Margin" Value="0,0,0,6"/>
        </Style>

        <Style TargetType="RadioButton">
            <Setter Property="Foreground" Value="{StaticResource TextSoft}"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>

        <Style TargetType="TextBlock" x:Key="SectionTitle">
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="{StaticResource Parchment}"/>
            <Setter Property="Margin" Value="0,0,0,6"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="250"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <Border Grid.Column="0" Background="#120D09" BorderBrush="#7D6233" BorderThickness="0,0,1,0">
            <Grid Margin="16">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <StackPanel>
                    <TextBlock Text="TEDETWEAK" FontSize="14" FontWeight="Bold" Foreground="#D6A84F"/>
                    <TextBlock Text="Grand Line Console" FontSize="24" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,2,0,4"/>
                    <TextBlock Text="Captain-grade optimization deck" Foreground="#BDAA84" FontSize="12" Margin="0,0,0,18"/>

                    <Button Name="BtnNavPreset" Style="{StaticResource NavButtonStyle}" Content="Crew Routes&#x0a;Preset di navigazione" Background="#3A2416"/>
                    <Button Name="BtnNavTweaks" Style="{StaticResource NavButtonStyle}" Content="Ship Systems&#x0a;Moduli e override"/>
                    <Button Name="BtnNavInfo" Style="{StaticResource NavButtonStyle}" Content="Captain Log&#x0a;Report e stato nave"/>
                </StackPanel>

                <Border Grid.Row="2" Background="#1C140E" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="10" Padding="12">
                    <StackPanel>
                        <TextBlock Text="Captain Intel" FontSize="15" FontWeight="Bold" Foreground="#F4D28C" Margin="0,0,0,8"/>
                        <TextBlock Text="Route: EAST BLUE" Name="TxtIntelRoute" Foreground="#FFF1CC" Margin="0,0,0,4"/>
                        <TextBlock Text="Risk: Controlled" Name="TxtIntelRisk" Foreground="#D9C7A0" Margin="0,0,0,4"/>
                        <TextBlock Text="Profile: Competitive Windows deck" Foreground="#BDAA84" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>
            </Grid>
        </Border>

        <Grid Grid.Column="1" Margin="16">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <Border Grid.Row="0" Background="#120E0A" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="14" Padding="18" Margin="0,0,0,12">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel>
                        <TextBlock Text="TedeTweak Grand Line Console" FontSize="30" FontWeight="Bold" Foreground="#FFF1CC"/>
                        <TextBlock Text="One Piece inspired command deck for competitive Windows optimization" Foreground="#D9C7A0" Margin="0,6,0,0"/>
                    </StackPanel>

                    <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                        <Border Name="ModeChipBorder" Background="#8C2F20" BorderBrush="#D6A84F" BorderThickness="1" CornerRadius="18" Padding="14,7" Margin="0,0,10,0">
                            <TextBlock Name="TxtModeChip" Text="EAST BLUE" Foreground="#FFF4DA" FontWeight="Bold"/>
                        </Border>
                        <Border Background="#16212B" BorderBrush="#38566B" BorderThickness="1" CornerRadius="18" Padding="12,7">
                            <TextBlock Text="Grand Line Ready" Foreground="#C8D5DE" FontWeight="SemiBold"/>
                        </Border>
                    </StackPanel>
                </Grid>
            </Border>

            <TabControl Name="MainTab" Grid.Row="1" Background="#120E0A" BorderBrush="#8A6735">
                <TabItem Header="Crew Routes">
                    <Grid Background="#120E0A" Margin="10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="340"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <StackPanel Grid.Column="0" Margin="0,0,14,0">
                            <Border Style="{StaticResource PanelCard}">
                                <StackPanel>
                                    <TextBlock Text="Crew Route" Style="{StaticResource SectionTitle}"/>
                                    <RadioButton Name="RbSafe" Content="East Blue — consigliato" IsChecked="True"/>
                                    <RadioButton Name="RbInsane" Content="Yonko Mode — tryhard"/>
                                    <RadioButton Name="RbCustom" Content="Grand Line Custom — manuale"/>
                                </StackPanel>
                            </Border>

                            <Border Style="{StaticResource PanelCard}">
                                <StackPanel>
                                    <TextBlock Text="Hardware manifest" Style="{StaticResource SectionTitle}"/>
                                    <TextBlock Text="Rete" Foreground="#E8D6AE" Margin="0,0,0,4"/>
                                    <ComboBox Name="CmbNetMode" SelectedIndex="0" Margin="0,0,0,10">
                                        <ComboBoxItem Content="LAN Ethernet"/>
                                        <ComboBoxItem Content="Wi-Fi"/>
                                    </ComboBox>
                                    <TextBlock Text="CPU" Foreground="#E8D6AE" Margin="0,0,0,4"/>
                                    <ComboBox Name="CmbCpu" SelectedIndex="0" Margin="0,0,0,10">
                                        <ComboBoxItem Content="AMD Ryzen"/>
                                        <ComboBoxItem Content="Intel Core"/>
                                    </ComboBox>
                                    <TextBlock Text="GPU" Foreground="#E8D6AE" Margin="0,0,0,4"/>
                                    <ComboBox Name="CmbGpu" SelectedIndex="1">
                                        <ComboBoxItem Content="AMD Radeon"/>
                                        <ComboBoxItem Content="NVIDIA GeForce"/>
                                        <ComboBoxItem Content="Intel Arc"/>
                                    </ComboBox>
                                </StackPanel>
                            </Border>
                        </StackPanel>

                        <Grid Grid.Column="1">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>

                            <UniformGrid Grid.Row="0" Columns="3" Margin="0,0,0,12">
                                <Border Margin="0,0,10,0" Background="#12344A" BorderBrush="#4FA4C2" BorderThickness="1" CornerRadius="14" Padding="16">
                                    <StackPanel>
                                        <TextBlock Text="GEAR 2" FontSize="20" FontWeight="Bold" Foreground="#FFF1CC"/>
                                        <TextBlock Text="Safe competitive route" Foreground="#BFE9E3" Margin="0,4,0,10"/>
                                        <TextBlock Text="Servizi base, gaming common, memory lite, cleanup e stabilità." TextWrapping="Wrap" Foreground="#E5F4F2"/>
                                    </StackPanel>
                                </Border>
                                <Border Margin="0,0,10,0" Background="#8C2F20" BorderBrush="#E7B45F" BorderThickness="1" CornerRadius="14" Padding="16">
                                    <StackPanel>
                                        <TextBlock Text="GEAR 4" FontSize="20" FontWeight="Bold" Foreground="#FFF1CC"/>
                                        <TextBlock Text="Aggressive battle route" Foreground="#FFD8BD" Margin="0,4,0,10"/>
                                        <TextBlock Text="Più spinta su scheduler, power, cleanup e moduli competitivi." TextWrapping="Wrap" Foreground="#FFF1E6"/>
                                    </StackPanel>
                                </Border>
                                <Border Background="#4B1A15" BorderBrush="#D6A84F" BorderThickness="1" CornerRadius="14" Padding="16">
                                    <StackPanel>
                                        <TextBlock Text="GEAR 5" FontSize="20" FontWeight="Bold" Foreground="#FFF1CC"/>
                                        <TextBlock Text="Peak and experimental" Foreground="#F2C7B8" Margin="0,4,0,10"/>
                                        <TextBlock Text="Massima spinta, profilo più rischioso, solo per test mirati." TextWrapping="Wrap" Foreground="#FEE9DE"/>
                                    </StackPanel>
                                </Border>
                            </UniformGrid>

                            <Border Grid.Row="1" Background="#1E1510" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="12" Padding="16">
                                <Grid>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="*"/>
                                    </Grid.RowDefinitions>
                                    <TextBlock Text="Route Description" FontSize="17" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,8"/>
                                    <TextBlock Name="TxtPresetDescription" Grid.Row="1" Text="East Blue: servizi base, debloat safe, power advanced, scheduler, input, USB, memory lite, cleanup pro, storage, display, cache, GPU helper, NIC advanced, overlay killer, validation report e gaming common." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,14"/>
                                    <Grid Grid.Row="2">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="260"/>
                                        </Grid.ColumnDefinitions>
                                        <StackPanel Margin="0,0,14,0">
                                            <TextBlock Text="Captain notes" FontSize="15" FontWeight="Bold" Foreground="#F4D28C" Margin="0,0,0,8"/>
                                            <TextBlock Text="Questa console mantiene la struttura tecnica del pannello originale, ma presenta i preset come vere rotte operative con identità visiva distinta e migliore leggibilità." TextWrapping="Wrap" Foreground="#D9C7A0"/>
                                        </StackPanel>
                                        <Border Grid.Column="1" Background="#241811" BorderBrush="#6B4D28" BorderThickness="1" CornerRadius="10" Padding="12">
                                            <StackPanel>
                                                <TextBlock Text="Battle telemetry" FontSize="14" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,8"/>
                                                <TextBlock Text="Risk level: Medium" Foreground="#E8D6AE" Margin="0,0,0,4"/>
                                                <TextBlock Text="Modules in route: 14" Foreground="#E8D6AE" Margin="0,0,0,4"/>
                                                <TextBlock Text="Recommended use: daily competitive" Foreground="#BDAA84" TextWrapping="Wrap"/>
                                            </StackPanel>
                                        </Border>
                                    </Grid>
                                </Grid>
                            </Border>
                        </Grid>
                    </Grid>
                </TabItem>

                <TabItem Header="Ship Systems">
                    <ScrollViewer Background="#120E0A">
                        <StackPanel Margin="10">
                            <Border Style="{StaticResource PanelCard}">
                                <StackPanel>
                                    <TextBlock Text="Hull Services &amp; Cargo Purge" Style="{StaticResource SectionTitle}"/>
                                    <TextBlock Text="Servizi Windows e rimozione bloatware selettiva." Foreground="#D9C7A0" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkServicesBase" Content="Services base reale"/>
                                    <CheckBox Name="ChkDebloatSafe" Content="Debloat safe reale"/>
                                    <CheckBox Name="ChkDebloatAggressive" Content="Debloat aggressive reale"/>
                                    <CheckBox Name="ChkDebloatExtreme" Content="Debloat extreme custom reale"/>
                                </StackPanel>
                            </Border>

                            <Border Style="{StaticResource PanelCard}">
                                <StackPanel>
                                    <TextBlock Text="Engine Core" Style="{StaticResource SectionTitle}"/>
                                    <TextBlock Text="Blocchi per input delay, reattività e frametime più stabili." Foreground="#D9C7A0" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkPowerAdvanced" Content="Power advanced reale"/>
                                    <CheckBox Name="ChkScheduler" Content="Scheduler MMCSS reale"/>
                                    <CheckBox Name="ChkInput" Content="Input tweaks reale"/>
                                    <CheckBox Name="ChkUsb" Content="USB low latency reale"/>
                                </StackPanel>
                            </Border>

                            <Border Style="{StaticResource PanelCard}">
                                <StackPanel>
                                    <TextBlock Text="Memory Deck" Style="{StaticResource SectionTitle}"/>
                                    <CheckBox Name="ChkMemoryLite" Content="Memory lite reale"/>
                                    <CheckBox Name="ChkMemoryAggressive" Content="Memory aggressive reale"/>
                                </StackPanel>
                            </Border>

                            <Border Style="{StaticResource PanelCard}">
                                <StackPanel>
                                    <TextBlock Text="Silent Deck Cleanup" Style="{StaticResource SectionTitle}"/>
                                    <CheckBox Name="ChkCleanupSafe" Content="Background cleanup safe reale"/>
                                </StackPanel>
                            </Border>

                            <Border Style="{StaticResource PanelCard}">
                                <StackPanel>
                                    <TextBlock Text="System Finish" Style="{StaticResource SectionTitle}"/>
                                    <CheckBox Name="ChkStorage" Content="Storage advanced reale"/>
                                    <CheckBox Name="ChkDisplay" Content="Display pipeline reale"/>
                                    <CheckBox Name="ChkCache" Content="Cache cleanup reale"/>
                                    <CheckBox Name="ChkCleanupPro" Content="Process cleanup safe pro reale"/>
                                </StackPanel>
                            </Border>

                            <Border Style="{StaticResource PanelCard}">
                                <StackPanel>
                                    <TextBlock Text="Battle Network &amp; Timing" Style="{StaticResource SectionTitle}"/>
                                    <CheckBox Name="ChkNetworkCommon" Content="Network common reale"/>
                                    <CheckBox Name="ChkAdapterMode" Content="Network adapter mode reale"/>
                                    <CheckBox Name="ChkNicAdvanced" Content="NIC advanced tuning reale"/>
                                    <CheckBox Name="ChkMsiMode" Content="MSI mode reale"/>
                                    <CheckBox Name="ChkBcd" Content="BCD timer tweaks reale"/>
                                </StackPanel>
                            </Border>

                            <Border Style="{StaticResource PanelCard}">
                                <StackPanel>
                                    <TextBlock Text="Cannons, GPU &amp; Targeting" Style="{StaticResource SectionTitle}"/>
                                    <CheckBox Name="ChkGpuHelper" Content="GPU vendor helper reale"/>
                                    <CheckBox Name="ChkGameExe" Content="Game exe generic reale"/>
                                </StackPanel>
                            </Border>

                            <Border Style="{StaticResource PanelCard}">
                                <StackPanel>
                                    <TextBlock Text="Captain Overrides" Style="{StaticResource SectionTitle}"/>
                                    <CheckBox Name="ChkOverlayKiller" Content="Overlay killer reale"/>
                                    <CheckBox Name="ChkSecurityOptional" Content="Security optional profile reale"/>
                                    <CheckBox Name="ChkVendorCleanup" Content="Vendor cleanup reale"/>
                                    <CheckBox Name="ChkValidationReport" Content="Validation report reale"/>
                                </StackPanel>
                            </Border>

                            <Border Style="{StaticResource PanelCard}">
                                <StackPanel>
                                    <TextBlock Text="Battle Orders" Style="{StaticResource SectionTitle}"/>
                                    <CheckBox Name="ChkGamingCommon" Content="Gaming common reale"/>
                                    <CheckBox Name="ChkFortniteSpecific" Content="Fortnite specific reale"/>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </ScrollViewer>
                </TabItem>

                <TabItem Header="Captain Log">
                    <Grid Background="#120E0A" Margin="10">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        <UniformGrid Columns="3" Margin="0,0,0,12">
                            <Border Margin="0,0,10,0" Background="#1E1510" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="12" Padding="14">
                                <StackPanel>
                                    <TextBlock Text="Current Route" FontSize="14" FontWeight="Bold" Foreground="#F4D28C"/>
                                    <TextBlock Text="East Blue" FontSize="22" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,6,0,4"/>
                                    <TextBlock Text="Balanced daily route" Foreground="#D9C7A0"/>
                                </StackPanel>
                            </Border>
                            <Border Margin="0,0,10,0" Background="#1E1510" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="12" Padding="14">
                                <StackPanel>
                                    <TextBlock Text="Hull Status" FontSize="14" FontWeight="Bold" Foreground="#F4D28C"/>
                                    <TextBlock Text="Ready" FontSize="22" FontWeight="Bold" Foreground="#BFE9E3" Margin="0,6,0,4"/>
                                    <TextBlock Text="No active warnings" Foreground="#D9C7A0"/>
                                </StackPanel>
                            </Border>
                            <Border Background="#1E1510" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="12" Padding="14">
                                <StackPanel>
                                    <TextBlock Text="Battle Risk" FontSize="14" FontWeight="Bold" Foreground="#F4D28C"/>
                                    <TextBlock Text="Controlled" FontSize="22" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,6,0,4"/>
                                    <TextBlock Text="Safe competitive window" Foreground="#D9C7A0"/>
                                </StackPanel>
                            </Border>
                        </UniformGrid>

                        <Border Grid.Row="1" Background="#1A130E" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="12" Padding="14">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                </Grid.RowDefinitions>
                                <TextBlock Text="Navigation records" FontSize="16" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,10"/>
                                <TextBox Name="TxtOutput" Grid.Row="1" Background="#0D0A08" Foreground="#E8D6AE" BorderBrush="#6E532A" BorderThickness="1" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" FontFamily="Consolas"/>
                            </Grid>
                        </Border>
                    </Grid>
                </TabItem>
            </TabControl>

            <Border Grid.Row="2" Background="#120E0A" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="14" Padding="14" Margin="0,12,0,0">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel>
                        <TextBlock Name="TxtStatus" Text="Status: nave pronta alla configurazione" Foreground="#FFF1CC" FontWeight="SemiBold"/>
                        <TextBlock Text="Set sail for optimization" Foreground="#BDAA84" Margin="0,4,0,0"/>
                    </StackPanel>

                    <StackPanel Grid.Column="1" Orientation="Horizontal">
                        <Button Name="BtnBackup" Style="{StaticResource ActionButtonStyle}" Background="#12344A" Content="Create Backup"/>
                        <Button Name="BtnRestore" Style="{StaticResource ActionButtonStyle}" Background="#4C2417" Content="Return to Port"/>
                        <Button Name="BtnApply" Style="{StaticResource ActionButtonStyle}" Background="#8C2F20" Content="Set Sail"/>
                    </StackPanel>
                </Grid>
            </Border>
        </Grid>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$MainTab = $window.FindName('MainTab')
$BtnNavPreset = $window.FindName('BtnNavPreset')
$BtnNavTweaks = $window.FindName('BtnNavTweaks')
$BtnNavInfo = $window.FindName('BtnNavInfo')
$RbSafe = $window.FindName('RbSafe')
$RbInsane = $window.FindName('RbInsane')
$RbCustom = $window.FindName('RbCustom')
$TxtModeLabel = $window.FindName('TxtModeLabel')
$TxtModeChip = $window.FindName('TxtModeChip')
$ModeChipBorder = $window.FindName('ModeChipBorder')
$TxtPresetDescription = $window.FindName('TxtPresetDescription')
$TxtStatus = $window.FindName('TxtStatus')
$BtnApply = $window.FindName('BtnApply')

$ChkServicesBase = $window.FindName('ChkServicesBase')
$ChkDebloatSafe = $window.FindName('ChkDebloatSafe')
$ChkDebloatAggressive = $window.FindName('ChkDebloatAggressive')
$ChkDebloatExtreme = $window.FindName('ChkDebloatExtreme')
$ChkDebloatUsers = $window.FindName('ChkDebloatUsers')
$ChkDebloatProvisioned = $window.FindName('ChkDebloatProvisioned')
$ChkPowerAdvanced = $window.FindName('ChkPowerAdvanced')
$ChkScheduler = $window.FindName('ChkScheduler')
$ChkInput = $window.FindName('ChkInput')
$ChkUsb = $window.FindName('ChkUsb')
$ChkMemoryLite = $window.FindName('ChkMemoryLite')
$ChkMemoryAggressive = $window.FindName('ChkMemoryAggressive')
$ChkCleanupSafe = $window.FindName('ChkCleanupSafe')
$ChkStorage = $window.FindName('ChkStorage')
$ChkDisplay = $window.FindName('ChkDisplay')
$ChkCache = $window.FindName('ChkCache')
$ChkCleanupPro = $window.FindName('ChkCleanupPro')
$ChkNetworkCommon = $window.FindName('ChkNetworkCommon')
$ChkNetworkAdapter = $window.FindName('ChkNetworkAdapter')
$ChkMSI = $window.FindName('ChkMSI')
$ChkBCD = $window.FindName('ChkBCD')
$ChkGpuVendor = $window.FindName('ChkGpuVendor')
$ChkGameExeGeneric = $window.FindName('ChkGameExeGeneric')
$TxtGameExePath = $window.FindName('TxtGameExePath')
$ChkNicAdvanced = $window.FindName('ChkNicAdvanced')
$ChkOverlayKiller = $window.FindName('ChkOverlayKiller')
$ChkSecurityOptional = $window.FindName('ChkSecurityOptional')
$ChkVendorCleanup = $window.FindName('ChkVendorCleanup')
$ChkValidationReport = $window.FindName('ChkValidationReport')
$ChkGaming = $window.FindName('ChkGaming')
$ChkFortnite = $window.FindName('ChkFortnite')

$BtnDebloatRecommended = $window.FindName('BtnDebloatRecommended')
$BtnDebloatAll = $window.FindName('BtnDebloatAll')
$BtnDebloatClear = $window.FindName('BtnDebloatClear')

$DebloatBoxes = [ordered]@{}
$DebloatBoxes['Clipchamp'] = $window.FindName('DbClipchamp')
$DebloatBoxes['Bing News'] = $window.FindName('DbBingNews')
$DebloatBoxes['Get Help'] = $window.FindName('DbGetHelp')
$DebloatBoxes['Get Started'] = $window.FindName('DbGetStarted')
$DebloatBoxes['Office Hub'] = $window.FindName('DbOfficeHub')
$DebloatBoxes['Solitaire'] = $window.FindName('DbSolitaire')
$DebloatBoxes['People'] = $window.FindName('DbPeople')
$DebloatBoxes['Skype'] = $window.FindName('DbSkype')
$DebloatBoxes['Teams Consumer'] = $window.FindName('DbTeams')
$DebloatBoxes['Xbox TCUI'] = $window.FindName('DbXboxTCUI')
$DebloatBoxes['Xbox App'] = $window.FindName('DbXboxApp')
$DebloatBoxes['Xbox Game Overlay'] = $window.FindName('DbXboxGameOverlay')
$DebloatBoxes['Xbox Gaming Overlay'] = $window.FindName('DbXboxGamingOverlay')
$DebloatBoxes['Xbox Identity Provider'] = $window.FindName('DbXboxIdentity')
$DebloatBoxes['Xbox Speech To Text'] = $window.FindName('DbXboxSpeech')
$DebloatBoxes['Phone Link'] = $window.FindName('DbPhoneLink')
$DebloatBoxes['Groove Music'] = $window.FindName('DbGroove')
$DebloatBoxes['Movies and TV'] = $window.FindName('DbMovies')
$DebloatBoxes['To Do'] = $window.FindName('DbTodo')
$DebloatBoxes['Family'] = $window.FindName('DbFamily')
$DebloatBoxes['Quick Assist'] = $window.FindName('DbQuickAssist')
$DebloatBoxes['Dev Home'] = $window.FindName('DbDevHome')
$DebloatBoxes['Feedback Hub'] = $window.FindName('DbFeedbackHub')
$DebloatBoxes['Maps'] = $window.FindName('DbMaps')
$DebloatBoxes['Camera'] = $window.FindName('DbCamera')
$DebloatBoxes['Sound Recorder'] = $window.FindName('DbSoundRecorder')
$DebloatBoxes['Alarms'] = $window.FindName('DbAlarms')
$DebloatBoxes['Mail and Calendar'] = $window.FindName('DbMailCalendar')

$RecommendedDebloat = @(
    'Clipchamp','Bing News','Get Help','Get Started','Office Hub','Solitaire','People','Skype','Teams Consumer',
    'Xbox TCUI','Xbox App','Xbox Game Overlay','Xbox Gaming Overlay','Xbox Identity Provider','Xbox Speech To Text',
    'Phone Link','Groove Music','Movies and TV','To Do','Family','Quick Assist','Dev Home','Feedback Hub','Maps'
)

function Get-SelectedDebloatItems {
    $items = @()
    foreach ($key in $DebloatBoxes.Keys) {
        if ($DebloatBoxes[$key].IsChecked) {
            $items += $key
        }
    }
    return $items
}

function Set-DebloatSelection {
    param([string[]]$Items)
    foreach ($key in $DebloatBoxes.Keys) {
        $DebloatBoxes[$key].IsChecked = $false
    }
    foreach ($name in $Items) {
        if ($DebloatBoxes.Contains($name)) {
            $DebloatBoxes[$name].IsChecked = $true
        }
    }
}

function Set-ModeDisplay {
    if ($RbSafe.IsChecked) {
        $TxtModeLabel.Text = 'Mode: SAFE'
        $TxtModeChip.Text = 'SAFE'
        $ModeChipBorder.Background = '#0D9488'
        $TxtPresetDescription.Text = 'East Blue: servizi base, debloat safe, power advanced, scheduler, input, USB, memory lite, cleanup pro, storage, display, cache, GPU helper, NIC advanced, overlay killer, validation report e gaming common.'
    }
    elseif ($RbInsane.IsChecked) {
        $TxtModeLabel.Text = 'Mode: INSANE'
        $TxtModeChip.Text = 'INSANE'
        $ModeChipBorder.Background = '#DC2626'
        $TxtPresetDescription.Text = 'Yonko Mode: aggiunge debloat aggressive, memory aggressive, security optional, vendor cleanup, game/network advanced, MSI, BCD, validation report e Fortnite specific.'
    }
    else {
        $TxtModeLabel.Text = 'Mode: CUSTOM'
        $TxtModeChip.Text = 'CUSTOM'
        $ModeChipBorder.Background = '#4B5563'
        $TxtPresetDescription.Text = 'Grand Line Custom: applica solo i gruppi selezionati nel tab Tweaks, incluso debloat extreme custom.'
    }
}

function Set-SafePreset {
    $ChkServicesBase.IsChecked = $true
    $ChkDebloatSafe.IsChecked = $true
    $ChkDebloatAggressive.IsChecked = $false
    $ChkDebloatExtreme.IsChecked = $false
    $ChkPowerAdvanced.IsChecked = $true
    $ChkScheduler.IsChecked = $true
    $ChkInput.IsChecked = $true
    $ChkUsb.IsChecked = $true
    $ChkMemoryLite.IsChecked = $true
    $ChkMemoryAggressive.IsChecked = $false
    $ChkCleanupSafe.IsChecked = $true
    $ChkStorage.IsChecked = $true
    $ChkDisplay.IsChecked = $true
    $ChkCache.IsChecked = $true
    $ChkCleanupPro.IsChecked = $true
    $ChkNetworkCommon.IsChecked = $true
    $ChkNetworkAdapter.IsChecked = $true
    $ChkMSI.IsChecked = $true
    $ChkBCD.IsChecked = $true
    $ChkGpuVendor.IsChecked = $true
    $ChkGameExeGeneric.IsChecked = $false
    $ChkNicAdvanced.IsChecked = $true
    $ChkOverlayKiller.IsChecked = $true
    $ChkSecurityOptional.IsChecked = $false
    $ChkVendorCleanup.IsChecked = $false
    $ChkValidationReport.IsChecked = $true
    $ChkGaming.IsChecked = $true
    $ChkFortnite.IsChecked = $false
    Set-DebloatSelection -Items $RecommendedDebloat
    $TxtStatus.Text = 'Preset EAST BLUE caricato.'
}

function Set-InsanePreset {
    $ChkServicesBase.IsChecked = $true
    $ChkDebloatSafe.IsChecked = $false
    $ChkDebloatAggressive.IsChecked = $true
    $ChkDebloatExtreme.IsChecked = $false
    $ChkPowerAdvanced.IsChecked = $true
    $ChkScheduler.IsChecked = $true
    $ChkInput.IsChecked = $true
    $ChkUsb.IsChecked = $true
    $ChkMemoryLite.IsChecked = $false
    $ChkMemoryAggressive.IsChecked = $true
    $ChkCleanupSafe.IsChecked = $true
    $ChkStorage.IsChecked = $true
    $ChkDisplay.IsChecked = $true
    $ChkCache.IsChecked = $true
    $ChkCleanupPro.IsChecked = $true
    $ChkNetworkCommon.IsChecked = $true
    $ChkNetworkAdapter.IsChecked = $true
    $ChkMSI.IsChecked = $true
    $ChkBCD.IsChecked = $true
    $ChkGpuVendor.IsChecked = $true
    $ChkGameExeGeneric.IsChecked = $false
    $ChkNicAdvanced.IsChecked = $true
    $ChkOverlayKiller.IsChecked = $true
    $ChkSecurityOptional.IsChecked = $true
    $ChkVendorCleanup.IsChecked = $true
    $ChkValidationReport.IsChecked = $true
    $ChkGaming.IsChecked = $true
    $ChkFortnite.IsChecked = $true
    Set-DebloatSelection -Items $RecommendedDebloat
    $TxtStatus.Text = 'Preset YONKO MODE caricato.'
}

function Set-CustomPreset {
    $ChkGpuVendor.IsChecked = $false
    $ChkGameExeGeneric.IsChecked = $false
    $ChkNicAdvanced.IsChecked = $false
    $ChkOverlayKiller.IsChecked = $false
    $ChkSecurityOptional.IsChecked = $false
    $ChkVendorCleanup.IsChecked = $false
    $ChkValidationReport.IsChecked = $false
    $TxtStatus.Text = 'Modalita GRAND LINE CUSTOM attiva. Modifica le checkbox a piacere.'
}

$RbSafe.Add_Checked({ Set-ModeDisplay; Set-SafePreset })
$RbInsane.Add_Checked({ Set-ModeDisplay; Set-InsanePreset })
$RbCustom.Add_Checked({ Set-ModeDisplay; Set-CustomPreset })
$BtnNavPreset.Add_Click({ $MainTab.SelectedIndex = 0 })
$BtnNavTweaks.Add_Click({ $MainTab.SelectedIndex = 1 })
$BtnNavInfo.Add_Click({ $MainTab.SelectedIndex = 2 })

$ChkMemoryLite.Add_Checked({ if ($ChkMemoryAggressive.IsChecked) { $ChkMemoryAggressive.IsChecked = $false } })
$ChkMemoryAggressive.Add_Checked({ if ($ChkMemoryLite.IsChecked) { $ChkMemoryLite.IsChecked = $false } })
$ChkDebloatSafe.Add_Checked({ if ($ChkDebloatAggressive.IsChecked) { $ChkDebloatAggressive.IsChecked = $false }; if ($ChkDebloatExtreme.IsChecked) { $ChkDebloatExtreme.IsChecked = $false } })
$ChkDebloatAggressive.Add_Checked({ if ($ChkDebloatSafe.IsChecked) { $ChkDebloatSafe.IsChecked = $false }; if ($ChkDebloatExtreme.IsChecked) { $ChkDebloatExtreme.IsChecked = $false } })
$ChkDebloatExtreme.Add_Checked({ if ($ChkDebloatSafe.IsChecked) { $ChkDebloatSafe.IsChecked = $false }; if ($ChkDebloatAggressive.IsChecked) { $ChkDebloatAggressive.IsChecked = $false } })

$BtnDebloatRecommended.Add_Click({ Set-DebloatSelection -Items $RecommendedDebloat; $TxtStatus.Text = 'Debloat recommended selezionato.' })
$BtnDebloatAll.Add_Click({ Set-DebloatSelection -Items @($DebloatBoxes.Keys); $TxtStatus.Text = 'Tutti i debloat selezionati.'
    Update-TedeDynamicInfo -HardwareBlock $TxtHardwareInfo -WarningsBlock $TxtWarnings -RiskBlock $TxtRiskLevel -CmbPreset $CmbPreset -ChkDebloatAggressive $ChkDebloatAggressive -ChkDebloatExtreme $ChkDebloatExtreme -ChkNetworkCommon $ChkNetworkCommon -ChkNetworkAdapter $ChkNetworkAdapter -ChkMSI $ChkMSI -ChkBCD $ChkBCD -ChkCleanupPro $ChkCleanupPro })
$BtnDebloatClear.Add_Click({ Set-DebloatSelection -Items @(); $TxtStatus.Text = 'Debloat custom pulito.'
    Update-TedeDynamicInfo -HardwareBlock $TxtHardwareInfo -WarningsBlock $TxtWarnings -RiskBlock $TxtRiskLevel -CmbPreset $CmbPreset -ChkDebloatAggressive $ChkDebloatAggressive -ChkDebloatExtreme $ChkDebloatExtreme -ChkNetworkCommon $ChkNetworkCommon -ChkNetworkAdapter $ChkNetworkAdapter -ChkMSI $ChkMSI -ChkBCD $ChkBCD -ChkCleanupPro $ChkCleanupPro })

$BtnRestoreBackup.Add_Click({
    Ensure-RunAsAdmin
    Initialize-TedeWorkspace
    $items = Restore-LatestTedeBackup
    foreach ($entry in $items) { Write-TedeLog $entry 'RESTORE' }
    $TxtOutput.Text = ($items -join [Environment]::NewLine)
})

$BtnOpenData.Add_Click({
    Initialize-TedeWorkspace
    Open-TedePath -Path $script:TedeDataRoot
})

$BtnApply.Add_Click({
    $done = New-Object System.Collections.Generic.List[string]
    $selected = New-Object System.Collections.Generic.List[string]

    if ($ChkServicesBase.IsChecked) { $selected.Add('Services base') }
    if ($ChkDebloatSafe.IsChecked) { $selected.Add('Debloat safe') }
    if ($ChkDebloatAggressive.IsChecked) { $selected.Add('Debloat aggressive') }
    if ($ChkDebloatExtreme.IsChecked) { $selected.Add('Debloat extreme custom') }
    if ($ChkPowerAdvanced.IsChecked) { $selected.Add('Power advanced') }
    if ($ChkScheduler.IsChecked) { $selected.Add('Scheduler / MMCSS') }
    if ($ChkInput.IsChecked) { $selected.Add('Input tweaks') }
    if ($ChkUsb.IsChecked) { $selected.Add('USB low latency') }
    if ($ChkMemoryLite.IsChecked) { $selected.Add('Memory lite') }
    if ($ChkMemoryAggressive.IsChecked) { $selected.Add('Memory aggressive') }
    if ($ChkCleanupSafe.IsChecked) { $selected.Add('Background cleanup safe') }
    if ($ChkStorage.IsChecked) { $selected.Add('Storage advanced') }
    if ($ChkDisplay.IsChecked) { $selected.Add('Display pipeline') }
    if ($ChkCache.IsChecked) { $selected.Add('Cache cleanup') }
    if ($ChkCleanupPro.IsChecked) { $selected.Add('Process cleanup safe pro') }
    if ($ChkNetworkCommon.IsChecked) { $selected.Add('Network common') }
    if ($ChkNetworkAdapter.IsChecked) { $selected.Add('Network adapter mode') }
    if ($ChkMSI.IsChecked) { $selected.Add('MSI mode') }
    if ($ChkBCD.IsChecked) { $selected.Add('BCD / timer tweaks') }
    if ($ChkGpuVendor.IsChecked) { $selected.Add('GPU vendor-specific helper') }
    if ($ChkGameExeGeneric.IsChecked) { $selected.Add('Game EXE generic flags') }
    if ($ChkNicAdvanced.IsChecked) { $selected.Add('NIC advanced fine tuning') }
    if ($ChkOverlayKiller.IsChecked) { $selected.Add('Overlay killer') }
    if ($ChkSecurityOptional.IsChecked) { $selected.Add('Security optional profile') }
    if ($ChkVendorCleanup.IsChecked) { $selected.Add('Vendor cleanup') }
    if ($ChkValidationReport.IsChecked) { $selected.Add('Validation report') }
    if ($ChkGaming.IsChecked) { $selected.Add('Gaming common') }
    if ($ChkFortnite.IsChecked) { $selected.Add('Fortnite specific') }

    $riskNow = Get-TedeRiskLevel -HasExtreme ([bool]$ChkDebloatExtreme.IsChecked) -HasBCD ([bool]$ChkBCD.IsChecked) -HasMSI ([bool]$ChkMSI.IsChecked) -HasNetwork ([bool]($ChkNetworkCommon.IsChecked -or $ChkNetworkAdapter.IsChecked -or $ChkNicAdvanced.IsChecked)) -HasAggressiveDebloat ([bool]$ChkDebloatAggressive.IsChecked) -HasCleanup ([bool]($ChkCleanupPro.IsChecked -or $ChkOverlayKiller.IsChecked))
    $warnNow = Get-TedeWarningMessages -HasExtreme ([bool]$ChkDebloatExtreme.IsChecked) -HasBCD ([bool]$ChkBCD.IsChecked) -HasMSI ([bool]$ChkMSI.IsChecked) -HasNetwork ([bool]($ChkNetworkCommon.IsChecked -or $ChkNetworkAdapter.IsChecked -or $ChkNicAdvanced.IsChecked)) -HasAggressiveDebloat ([bool]$ChkDebloatAggressive.IsChecked) -HasCleanup ([bool]($ChkCleanupPro.IsChecked -or $ChkOverlayKiller.IsChecked))
    if (-not (Confirm-TedeSensitiveSelection -RiskText $riskNow -WarningText $warnNow)) {
       $TxtStatus.Text = "Applicazione annullata dall'utente."
        return
    }

    if ($selected.Count -eq 0) {
        $TxtStatus.Text = 'Nessun tweak selezionato.'
        [System.Windows.MessageBox]::Show('Non hai selezionato nessun tweak.', 'TedeTweak') | Out-Null
        return
    }

    try {
        if ($ChkServicesBase.IsChecked) {
            foreach ($item in (Apply-ServicesBase)) { $done.Add($item) }
        }

        if ($ChkDebloatSafe.IsChecked) {
            foreach ($item in (Apply-DebloatSafe)) { $done.Add($item) }
        }
        elseif ($ChkDebloatAggressive.IsChecked) {
            foreach ($item in (Apply-DebloatAggressive)) { $done.Add($item) }
        }
        elseif ($ChkDebloatExtreme.IsChecked) {
            $customItems = Get-SelectedDebloatItems
            if ($customItems.Count -eq 0) {
                $done.Add('SKIP Debloat extreme: nessuna checkbox selezionata')
            }
            else {
                foreach ($item in (Apply-DebloatSelection -Items $customItems -RemoveForUsers ([bool]$ChkDebloatUsers.IsChecked) -RemoveProvisioned ([bool]$ChkDebloatProvisioned.IsChecked))) { $done.Add($item) }
            }
        }

        if ($ChkPowerAdvanced.IsChecked) {
            foreach ($item in (Apply-PowerAdvanced)) { $done.Add($item) }
        }

        if ($ChkScheduler.IsChecked) {
            foreach ($item in (Apply-SchedulerMMCSS)) { $done.Add($item) }
        }

        if ($ChkInput.IsChecked) {
            foreach ($item in (Apply-InputTweaks)) { $done.Add($item) }
        }

        if ($ChkUsb.IsChecked) {
            foreach ($item in (Apply-UsbLowLatency)) { $done.Add($item) }
        }

        if ($ChkMemoryAggressive.IsChecked) {
            foreach ($item in (Apply-MemoryAggressive)) { $done.Add($item) }
        }
        elseif ($ChkMemoryLite.IsChecked) {
            foreach ($item in (Apply-MemoryLite)) { $done.Add($item) }
        }

        if ($ChkCleanupSafe.IsChecked) {
            foreach ($item in (Apply-BackgroundCleanupSafe)) { $done.Add($item) }
        }

        if ($ChkStorage.IsChecked) {
            foreach ($item in (Apply-StorageAdvanced)) { $done.Add($item) }
        }

        if ($ChkDisplay.IsChecked) {
            foreach ($item in (Apply-DisplayPipeline)) { $done.Add($item) }
        }

        if ($ChkCache.IsChecked) {
            foreach ($item in (Apply-CacheCleanup)) { $done.Add($item) }
        }

        if ($ChkCleanupPro.IsChecked) {
            foreach ($item in (Apply-ProcessCleanupSafePro)) { $done.Add($item) }
        }

        if ($ChkNetworkCommon.IsChecked) {
            foreach ($item in (Apply-NetworkCommon)) { $done.Add($item) }
        }

        if ($ChkNetworkAdapter.IsChecked) {
            $mode = 'LAN'
            if ($window.FindName('CmbNetMode').SelectedIndex -eq 1) { $mode = 'Wi-Fi' }
            foreach ($item in (Apply-NetworkAdapterMode -Mode $mode)) { $done.Add($item) }
        }

        if ($ChkMSI.IsChecked) {
            foreach ($item in (Apply-MSIMode)) { $done.Add($item) }
        }

        if ($ChkBCD.IsChecked) {
            foreach ($item in (Apply-BCDTimerTweaks)) { $done.Add($item) }
        }

        if ($ChkGpuVendor.IsChecked) {
            foreach ($item in (Apply-GpuVendorSpecific)) { $done.Add($item) }
        }

        if ($ChkGameExeGeneric.IsChecked) {
            foreach ($item in (Apply-GameExeGeneric -ExePath $TxtGameExePath.Text)) { $done.Add($item) }
        }

        if ($ChkNicAdvanced.IsChecked) {
            $mode = 'LAN'
            if ($window.FindName('CmbNetMode').SelectedIndex -eq 1) { $mode = 'Wi-Fi' }
            foreach ($item in (Apply-NicAdvancedTuning -Mode $mode)) { $done.Add($item) }
        }

        if ($ChkOverlayKiller.IsChecked) {
            foreach ($item in (Apply-OverlayKiller)) { $done.Add($item) }
        }

        if ($ChkSecurityOptional.IsChecked) {
            foreach ($item in (Apply-SecurityOptionalProfile)) { $done.Add($item) }
        }

        if ($ChkVendorCleanup.IsChecked) {
            foreach ($item in (Apply-VendorCleanup)) { $done.Add($item) }
        }

        if ($ChkValidationReport.IsChecked) {
            $done.Add((New-TedeValidationReport))
        }

        if ($ChkGaming.IsChecked) {
            foreach ($item in (Apply-GamingCommon)) { $done.Add($item) }
        }

        if ($ChkFortnite.IsChecked) {
            foreach ($item in (Apply-FortniteSpecific)) { $done.Add($item) }
        }

        $summary = @()
        $summary += 'Selezionati:'
        $summary += ''
        foreach ($s in $selected) { $summary += '- ' + $s }
        if ($ChkDebloatExtreme.IsChecked) {
            $summary += ''
            $summary += 'Debloat extreme scelti:'
            foreach ($d in (Get-SelectedDebloatItems)) { $summary += '- ' + $d }
        }
        $summary += ''
        $summary += 'Risultati:'
        $summary += ''
        foreach ($d in $done) { $summary += '- ' + $d }

        $TxtStatus.Text = 'Tweaks applicati: ' + $done.Count
        [System.Windows.MessageBox]::Show(($summary -join "`n"), 'TedeTweak') | Out-Null
    }
    catch {
        $TxtStatus.Text = 'Errore: ' + $_.Exception.Message
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'TedeTweak - Errore') | Out-Null
    }
})

Set-ModeDisplay
Set-SafePreset
$MainTab.SelectedIndex = 0

$null = $window.ShowDialog()
