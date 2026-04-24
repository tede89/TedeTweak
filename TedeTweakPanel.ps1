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

function Get-TedeRiskLevel {
    param(
        [bool]$HasExtreme = $false,
        [bool]$HasSecurity = $false,
        [bool]$HasBCD = $false,
        [bool]$HasMSI = $false,
        [bool]$HasMemoryAggressive = $false
    )

    $score = 0
    if ($HasExtreme)          { $score += 3 }
    if ($HasSecurity)         { $score += 3 }
    if ($HasBCD)              { $score += 2 }
    if ($HasMSI)              { $score += 1 }
    if ($HasMemoryAggressive) { $score += 1 }

    if ($score -ge 6) { return 'ALTO' }
    if ($score -ge 3) { return 'MEDIO' }
    return 'BASSO'
}

function Get-TedeWarningMessages {
    param(
        [bool]$HasExtreme = $false,
        [bool]$HasSecurity = $false,
        [bool]$HasBCD = $false,
        [bool]$HasMSI = $false,
        [bool]$HasMemoryAggressive = $false
    )

    $warn = New-Object System.Collections.Generic.List[string]

    if ($HasExtreme) {
        $warn.Add('Debloat extreme puo rimuovere componenti/app che potresti voler tenere.')
    }
    if ($HasSecurity) {
        $warn.Add('Security optional puo disattivare VBS, HVCI, LSA e hypervisor.')
    }
    if ($HasBCD) {
        $warn.Add('BCD timer tweaks richiedono attenzione e spesso un riavvio.')
    }
    if ($HasMSI) {
        $warn.Add('MSI mode non e ideale su ogni device/driver.')
    }
    if ($HasMemoryAggressive) {
        $warn.Add('Memory aggressive disattiva Memory Compression.')
    }

    if ($warn.Count -eq 0) {
        $warn.Add('Nessun warning sensibile rilevato.')
    }

    return ($warn -join "`r`n")
}

function Confirm-TedeSensitiveSelection {
    param(
        [string]$RiskText,
        [string]$WarningText
    )

    $msg = @"
Livello rischio: $RiskText

Avvisi:
$WarningText

Vuoi continuare?
"@

    $res = [System.Windows.MessageBox]::Show(
        $msg,
        'TedeTweak - Conferma modifiche sensibili',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )

    return ($res -eq [System.Windows.MessageBoxResult]::Yes)
}

function Get-TedeSelectedBlocks {
    param(
        [object]$ChkDebloatExtreme,
        [object]$ChkSecurityOptional,
        [object]$ChkBCD,
        [object]$ChkMSI,
        [object]$ChkMemoryAggressive
    )

    [pscustomobject]@{
        HasExtreme          = [bool]($ChkDebloatExtreme -and $ChkDebloatExtreme.IsChecked)
        HasSecurity         = [bool]($ChkSecurityOptional -and $ChkSecurityOptional.IsChecked)
        HasBCD              = [bool]($ChkBCD -and $ChkBCD.IsChecked)
        HasMSI              = [bool]($ChkMSI -and $ChkMSI.IsChecked)
        HasMemoryAggressive = [bool]($ChkMemoryAggressive -and $ChkMemoryAggressive.IsChecked)
    }
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
        'AJModer',
        'XblAuthManager',
        'XblGameSave',
        'XboxGipSvc',
        'XboxNetApiSvc'
        'ndu',
        'WSearch',
        'TabletInputService',
        'PrintNotify',
        'lfsvc',
        'wisvc',
        'SharedAccess',
        'SSDPSRV',
        'upnphost',
        'lmhosts',
        'WpcMonSvc',
        'icssvc',
        'PhoneSvc',
        'SessionEnv',
        'TermService',
        'HvHost',
        'vmickvpexchange',
        'vmicguestinterface',
        'vmicheartbeat',
        'vmicshutdown',
        'vmictimesync',
        'vmicvss',
        'FontCache',
        'Wecsvc',
        'WinRM',
        'NcaSvc'
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

    # QUELLO CHE C'ERA GIA'
    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'DisablePagingExecutive' -Value 1
    $applied += 'DisablePagingExecutive = 1'
    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'LargeSystemCache' -Value 0
    $applied += 'LargeSystemCache = 0'

    # KERNEL IN RAM + OTTIMIZZAZIONI NUOVE
    $mmPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    Set-ItemProperty -Path $mmPath -Name 'ClearPageFileAtShutdown'    -Value 0 -Type DWord -Force | Out-Null
    $applied += 'ClearPageFileAtShutdown = 0'
    Set-ItemProperty -Path $mmPath -Name 'NonPagedPoolQuota'           -Value 0 -Type DWord -Force | Out-Null
    $applied += 'NonPagedPoolQuota = 0'
    Set-ItemProperty -Path $mmPath -Name 'NonPagedPoolSize'            -Value 0 -Type DWord -Force | Out-Null
    $applied += 'NonPagedPoolSize = 0'
    Set-ItemProperty -Path $mmPath -Name 'PagedPoolQuota'              -Value 0 -Type DWord -Force | Out-Null
    $applied += 'PagedPoolQuota = 0'
    Set-ItemProperty -Path $mmPath -Name 'PagedPoolSize'               -Value 192 -Type DWord -Force | Out-Null
    $applied += 'PagedPoolSize = 192'
    Set-ItemProperty -Path $mmPath -Name 'SessionPoolSize'             -Value 48 -Type DWord -Force | Out-Null
    $applied += 'SessionPoolSize = 48'
    Set-ItemProperty -Path $mmPath -Name 'SessionViewSize'             -Value 48 -Type DWord -Force | Out-Null
    $applied += 'SessionViewSize = 48'
    Set-ItemProperty -Path $mmPath -Name 'SystemPages'                 -Value 0 -Type DWord -Force | Out-Null
    $applied += 'SystemPages = 0 (auto)'

    # DISABLE MEMORY COMPRESSION
    try {
        Disable-MMAgent -mc -ErrorAction SilentlyContinue | Out-Null
        $applied += 'Memory Compression = disabled'
    } catch { $applied += 'SKIP Memory Compression' }

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

    # MOUSE 1:1
    Set-RegString -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed'      -Value '0'
    $applied += 'MouseSpeed = 0'
    Set-RegString -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0'
    $applied += 'MouseThreshold1 = 0'
    Set-RegString -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0'
    $applied += 'MouseThreshold2 = 0'
    Set-RegString -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseHoverTime'  -Value '400'
    $applied += 'MouseHoverTime = 400'

    # KEYBOARD DELAY MIN / SPEED MAX
    Set-RegString -Path 'HKCU:\Control Panel\Keyboard' -Name 'KeyboardSpeed' -Value '31'
    $applied += 'KeyboardSpeed = 31'
    Set-RegString -Path 'HKCU:\Control Panel\Keyboard' -Name 'KeyboardDelay' -Value '0'
    $applied += 'KeyboardDelay = 0'

    # ACCESSIBILITY KEYS OFF (eliminano polling delay nascosto)
    Set-RegString -Path 'HKCU:\Control Panel\Accessibility\StickyKeys'      -Name 'Flags' -Value '506'
    $applied += 'StickyKeys Flags = 506'
    Set-RegString -Path 'HKCU:\Control Panel\Accessibility\MouseKeys'       -Name 'Flags' -Value '506'
    $applied += 'MouseKeys Flags = 506'
    Set-RegString -Path 'HKCU:\Control Panel\Accessibility\ToggleKeys'      -Name 'Flags' -Value '506'
    $applied += 'ToggleKeys Flags = 506'
    Set-RegString -Path 'HKCU:\Control Panel\Accessibility\Keyboard Response' -Name 'Flags' -Value '506'
    $applied += 'FilterKeys Flags = 506'

    # MOUSE POINTER PRECISION OFF (raw input puro)
    Set-RegDword -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSensitivity' -Value 10
    $applied += 'MouseSensitivity = 10'

    # FOREGROUND INPUT BOOST
    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 26
    $applied += 'Win32PrioritySeparation = 26'

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
    $applied += 'Win32PrioritySeparation = 26'

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

    # QUELLO CHE C'ERA GIA'
    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\I/O System' -Name 'IoVerifierLevel' -Value 0
    $applied += 'IoVerifierLevel = 0'
    try { fsutil behavior set DisableDeleteNotify 0 | Out-Null; $applied += 'TRIM = enabled' } catch { $applied += 'SKIP TRIM' }

    # NTFS OTTIMIZZAZIONE
    try { fsutil behavior set disable8dot3 1       | Out-Null; $applied += 'disable8dot3 = 1' }       catch { $applied += 'SKIP 8dot3' }
    try { fsutil behavior set disablelastaccess 1  | Out-Null; $applied += 'disablelastaccess = 1' }  catch { $applied += 'SKIP lastaccess' }
    try { fsutil behavior set disablecompression 1 | Out-Null; $applied += 'disablecompression = 1' } catch { $applied += 'SKIP compression' }
    try { fsutil behavior set mftzone 2            | Out-Null; $applied += 'mftzone = 2' }            catch { $applied += 'SKIP mftzone' }

    # NTFS REGISTRY
    $fsPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    Set-ItemProperty -Path $fsPath -Name 'LargeSystemCache'              -Value 0 -Type DWord -Force | Out-Null
    $applied += 'LargeSystemCache = 0'
    Set-ItemProperty -Path $fsPath -Name 'NtfsMemoryUsage'               -Value 2 -Type DWord -Force | Out-Null
    $applied += 'NtfsMemoryUsage = 2'
    Set-ItemProperty -Path $fsPath -Name 'NtfsDisable8dot3NameCreation'  -Value 1 -Type DWord -Force | Out-Null
    $applied += 'NtfsDisable8dot3NameCreation = 1'
    Set-ItemProperty -Path $fsPath -Name 'NtfsDisableLastAccessUpdate'   -Value 1 -Type DWord -Force | Out-Null
    $applied += 'NtfsDisableLastAccessUpdate = 1'

    return $applied
}

function Apply-DisplayPipeline {
    $applied = @()

    # QUELLO CHE C'ERA GIA'
    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Value 2
    $applied += 'HAGS = enabled'
    Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'GPU Priority' -Value 8
    $applied += 'GPU Priority = 8'
    Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'Priority' -Value 6
    $applied += 'Games Priority = 6'

    # GAMEBAR COMPLETAMENTE OFF
    $gbPath = 'HKCU:\Software\Microsoft\GameBar'
    if (-not (Test-Path $gbPath)) { New-Item -Path $gbPath -Force | Out-Null }
    Set-ItemProperty -Path $gbPath -Name 'AllowAutoGameMode'          -Value 0 -Type DWord -Force | Out-Null
    $applied += 'AllowAutoGameMode = 0'
    Set-ItemProperty -Path $gbPath -Name 'UseNexusForGameBarEnabled'  -Value 0 -Type DWord -Force | Out-Null
    $applied += 'UseNexusForGameBarEnabled = 0'
    Set-ItemProperty -Path $gbPath -Name 'ShowStartupPanel'           -Value 0 -Type DWord -Force | Out-Null
    $applied += 'ShowStartupPanel = 0'
    Set-ItemProperty -Path $gbPath -Name 'GamePanelStartupTipIndex'   -Value 3 -Type DWord -Force | Out-Null
    $applied += 'GamePanelStartupTipIndex = 3'

    # GAMEDVR OFF
    $dvrPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'
    if (-not (Test-Path $dvrPath)) { New-Item -Path $dvrPath -Force | Out-Null }
    Set-ItemProperty -Path $dvrPath -Name 'AllowGameDVR' -Value 0 -Type DWord -Force | Out-Null
    $applied += 'GameDVR = disabled'

    # GAME MODE OFF (peggiora frametime stabili)
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
    $applied += 'AutoGameMode = 0'

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

    # PACKET LOSS TWEAKS
    $tcpPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    Set-ItemProperty -Path $tcpPath -Name 'DefaultReceiveWindow'      -Value 256960  -Type DWord -Force | Out-Null
    $applied += 'DefaultReceiveWindow = 256960'
    Set-ItemProperty -Path $tcpPath -Name 'DefaultSendWindow'         -Value 256960  -Type DWord -Force | Out-Null
    $applied += 'DefaultSendWindow = 256960'
    Set-ItemProperty -Path $tcpPath -Name 'MaxDupAcks'                -Value 2       -Type DWord -Force | Out-Null
    $applied += 'MaxDupAcks = 2'
    Set-ItemProperty -Path $tcpPath -Name 'GlobalMaxTcpWindowSize'    -Value 65535   -Type DWord -Force | Out-Null
    $applied += 'GlobalMaxTcpWindowSize = 65535'
    Set-ItemProperty -Path $tcpPath -Name 'TcpTimedWaitDelay'         -Value 30      -Type DWord -Force | Out-Null
    $applied += 'TcpTimedWaitDelay = 30'
    Set-ItemProperty -Path $tcpPath -Name 'MaxUserPort'               -Value 65534   -Type DWord -Force | Out-Null
    $applied += 'MaxUserPort = 65534'
    Set-ItemProperty -Path $tcpPath -Name 'FastSendDatagramThreshold' -Value 1024    -Type DWord -Force | Out-Null
    $applied += 'FastSendDatagramThreshold = 1024'
    Set-ItemProperty -Path $tcpPath -Name 'DisableTaskOffload'        -Value 1       -Type DWord -Force | Out-Null
    $applied += 'DisableTaskOffload = 1'

    # QoS - libera 20% banda riservata
    $qosPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched'
    if (-not (Test-Path $qosPath)) { New-Item -Path $qosPath -Force | Out-Null }
    Set-ItemProperty -Path $qosPath -Name 'NonBestEffortLimit' -Value 0 -Type DWord -Force | Out-Null
    $applied += 'QoS NonBestEffortLimit = 0'

    # WiFi specifico
    $wcmPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy'
    if (-not (Test-Path $wcmPath)) { New-Item -Path $wcmPath -Force | Out-Null }
    Set-ItemProperty -Path $wcmPath -Name 'fMinimizeConnections' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
    $applied += 'WiFi fMinimizeConnections = 0'

        try {
        netsh winsock reset | Out-Null
        $applied += 'winsock reset'
    }
    catch {
        $applied += 'SKIP winsock reset'
    }

    try {
        netsh int ip reset | Out-Null
        $applied += 'ip reset'
    }
    catch {
        $applied += 'SKIP ip reset'
    }

    try {
        Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'TcpNumConnections' -Value 16777214
        $applied += 'TcpNumConnections = 16777214'
    }
    catch {
        $applied += 'SKIP TcpNumConnections'
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

function Apply-DnsOnly {
    param([string]$Mode)

    $applied = @()
    $adapter = Get-ActiveTedeAdapter -Mode $Mode
    if ($null -eq $adapter) {
        return 'SKIP DNS only: nessun adapter attivo'
    }

    try {
        netsh interface ip set dns name="$($adapter.Name)" static 1.1.1.1 primary | Out-Null
        netsh interface ip add dns name="$($adapter.Name)" 1.0.0.1 index=2 | Out-Null
        $applied += ('DNS Cloudflare impostato su ' + $adapter.Name)
    }
    catch {
        $applied += ('SKIP DNS only: ' + $_.Exception.Message)
    }

    return $applied
}

function Apply-TcpLatencyOnly {
    $applied = @()

    try {
        netsh interface tcp set global autotuninglevel=normal | Out-Null
        $applied += 'autotuninglevel normal'
    } catch { $applied += 'SKIP autotuninglevel' }

    try {
        netsh interface tcp set global rss=enabled | Out-Null
        $applied += 'rss enabled'
    } catch { $applied += 'SKIP rss' }

    try {
        netsh interface tcp set global rsc=disabled | Out-Null
        $applied += 'rsc disabled'
    } catch { $applied += 'SKIP rsc' }

    try {
        netsh interface tcp set global ecncapability=disabled | Out-Null
        $applied += 'ecncapability disabled'
    } catch { $applied += 'SKIP ecncapability' }

    try {
        netsh interface tcp set global timestamps=disabled | Out-Null
        $applied += 'timestamps disabled'
    } catch { $applied += 'SKIP timestamps' }

    try {
        $ifaces = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' -ErrorAction SilentlyContinue
        $count = 0
        foreach ($iface in $ifaces) {
            New-ItemProperty -Path $iface.PSPath -Name 'TcpAckFrequency' -PropertyType DWord -Value 1 -Force | Out-Null
            New-ItemProperty -Path $iface.PSPath -Name 'TCPNoDelay' -PropertyType DWord -Value 1 -Force | Out-Null
            New-ItemProperty -Path $iface.PSPath -Name 'TcpDelAckTicks' -PropertyType DWord -Value 0 -Force | Out-Null
            $count++
        }
        $applied += ('TCP low latency su interfacce: ' + $count)
    }
    catch {
        $applied += ('SKIP TCP interface tuning: ' + $_.Exception.Message)
    }

    return $applied
}

function Apply-NduOffOnly {
    $applied = @()
    try {
        Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Ndu' -Name 'Start' -Value 4
        $applied += 'Ndu Start = 4'
    }
    catch {
        $applied += ('SKIP Ndu off: ' + $_.Exception.Message)
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

    # QUELLO CHE C'ERA GIA'
    try { bcdedit /set disabledynamictick yes    | Out-Null; $applied += 'disabledynamictick = yes' }    catch { $applied += 'SKIP disabledynamictick' }
    try { bcdedit /set useplatformtick yes       | Out-Null; $applied += 'useplatformtick = yes' }       catch { $applied += 'SKIP useplatformtick' }
    try { bcdedit /set tscsyncpolicy Enhanced    | Out-Null; $applied += 'tscsyncpolicy = Enhanced' }    catch { $applied += 'SKIP tscsyncpolicy' }
    try { bcdedit /set hypervisorlaunchtype off  | Out-Null; $applied += 'hypervisorlaunchtype = off' }  catch { $applied += 'SKIP hypervisorlaunchtype' }

    # BOOT OTTIMIZZAZIONE NUOVA
    try { bcdedit /set bootlog no                | Out-Null; $applied += 'bootlog = no' }                catch { $applied += 'SKIP bootlog' }
    try { bcdedit /set quietboot yes             | Out-Null; $applied += 'quietboot = yes' }             catch { $applied += 'SKIP quietboot' }
    try { bcdedit /set bootmenupolicy Legacy     | Out-Null; $applied += 'bootmenupolicy = Legacy' }     catch { $applied += 'SKIP bootmenupolicy' }
    try { bcdedit /set nx AlwaysOff             | Out-Null; $applied += 'nx = AlwaysOff' }              catch { $applied += 'SKIP nx' }
    try { bcdedit /set ems no                   | Out-Null; $applied += 'ems = no' }                    catch { $applied += 'SKIP ems' }

    # HIBERNATION OFF + FAST STARTUP OFF
    try { powercfg /h off                        | Out-Null; $applied += 'Hibernation = off' }           catch { $applied += 'SKIP hibernation' }
    try {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Value 0 -Type DWord -Force | Out-Null
        $applied += 'Fast Startup = disabled'
    } catch { $applied += 'SKIP Fast Startup' }

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
            foreach ($proc in @('RadeonSoftware','AMDRSServ')) {
                $applied += Stop-ProcessSafe -Name $proc
            }
            $applied += Apply-AmdGpuTweaks
            $applied += 'Profilo AMD helper applicato'
        }
        'NVIDIA' {
            foreach ($proc in @('NVIDIA Share','NVIDIA App','nvsphelper64')) {
                $applied += Stop-ProcessSafe -Name $proc
            }
            $applied += Apply-NvidiaGpuTweaks
            $applied += 'Profilo NVIDIA helper applicato'
        }
        'Intel' {
            foreach ($proc in @('IntelGraphicsSoftware','igfxCUIService')) {
                $applied += Stop-ProcessSafe -Name $proc
            }
            $applied += 'Profilo Intel helper applicato'
        }
        default {
            $applied += 'SKIP vendor-specific: GPU non riconosciuta'
        }
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

function Test-TedeRegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Expected
    )

    try {
        $value = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
        if ($value -eq $Expected) {
            return "OK  | $Name = $value"
        }
        return "FAIL| $Name = $value (atteso: $Expected)"
    }
    catch {
        return "SKIP| $Name non trovato su $Path"
    }
}

function Test-TedeServiceStartupDisabled {
    param([string]$Name)

    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        if ($svc.StartType -eq 'Disabled') {
            return "OK  | Servizio $Name disabilitato"
        }
        return "FAIL| Servizio $Name startup = $($svc.StartType)"
    }
    catch {
        return "SKIP| Servizio $Name non trovato"
    }
}

function Test-TedePowerScheme {
    try {
        $out = powercfg -getactivescheme 2>$null | Out-String
        if ($out -match 'Ultimate Performance') {
            return 'OK  | Power plan Ultimate Performance attivo'
        }
        return ('SKIP| Power plan attivo: ' + $out.Trim())
    }
    catch {
        return 'SKIP| Impossibile leggere il power plan attivo'
    }
}

function New-TedePostCheckReport {
    Initialize-TedeWorkspace

    $reportRoot = Join-Path $script:TedeDataRoot 'Reports'
    if (-not (Test-Path $reportRoot)) {
        New-Item -Path $reportRoot -ItemType Directory -Force | Out-Null
    }

    $file = Join-Path $reportRoot ("postcheck_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add('TEDETWEAK POST CHECK')
    $lines.Add('Date: ' + (Get-Date))
    $lines.Add('')

    $lines.Add('[Scheduler / MMCSS]')
    $lines.Add((Test-TedeRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Expected 38))
    $lines.Add((Test-TedeRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'SystemResponsiveness' -Expected 0))
    $lines.Add((Test-TedeRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex' -Expected 4294967295))
    $lines.Add('')

    $lines.Add('[Gaming]')
    $lines.Add((Test-TedeRegistryValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Expected 0))
    $lines.Add((Test-TedeRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Expected 2))
    $lines.Add('')

    $lines.Add('[Memory]')
    $lines.Add((Test-TedeRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'DisablePagingExecutive' -Expected 1))
    $lines.Add((Test-TedeRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'LargeSystemCache' -Expected 0))
    $lines.Add('')

    $lines.Add('[Network]')
    $lines.Add((Test-TedeRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Ndu' -Name 'Start' -Expected 4))
    $lines.Add('')

    $lines.Add('[Services]')
    $lines.Add((Test-TedeServiceStartupDisabled -Name 'SysMain'))
    $lines.Add((Test-TedeServiceStartupDisabled -Name 'DiagTrack'))
    $lines.Add('')

    $lines.Add('[Power]')
    $lines.Add((Test-TedePowerScheme))

    Set-Content -Path $file -Value $lines -Encoding UTF8
    Write-TedeLog ("Post-check report creato: " + $file)

    return $file
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


function Apply-NvidiaGpuTweaks {
    $applied = @()

    $nvPaths = @(
        'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm',
        'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global',
        'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\NVTweak'
    )
    foreach ($p in $nvPaths) {
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    }

    $nvt = 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\NVTweak'
    $nvg = 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global'
    $nvr = 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm'

    # POWERMIZER - GPU sempre a clock massimo
    Set-ItemProperty -Path $nvt -Name 'PowerMizerEnable'     -Value 0 -Type DWord -Force | Out-Null
    $applied += 'NVIDIA PowerMizerEnable = 0'
    Set-ItemProperty -Path $nvt -Name 'PowerMizerLevel'      -Value 1 -Type DWord -Force | Out-Null
    $applied += 'NVIDIA PowerMizerLevel = 1 (max perf)'
    Set-ItemProperty -Path $nvt -Name 'PowerMizerLevelAC'    -Value 1 -Type DWord -Force | Out-Null
    $applied += 'NVIDIA PowerMizerLevelAC = 1'
    Set-ItemProperty -Path $nvt -Name 'DisplayPowerSaving'   -Value 0 -Type DWord -Force | Out-Null
    $applied += 'NVIDIA DisplayPowerSaving = 0'

    # CLOCK STABILE - no boost dinamico instabile
    Set-ItemProperty -Path $nvt -Name 'NvCplAdjustableClockFrequencies' -Value 1 -Type DWord -Force | Out-Null
    $applied += 'NVIDIA AdjustableClockFrequencies = 1'

    # PREEMPTION OFF - meno interruzioni durante rendering
    Set-ItemProperty -Path $nvg -Name 'EnableMidBufferPreemption'    -Value 0 -Type DWord -Force | Out-Null
    $applied += 'NVIDIA MidBufferPreemption = 0'
    Set-ItemProperty -Path $nvg -Name 'EnableMidGfxPreemptionVGPU'   -Value 0 -Type DWord -Force | Out-Null
    $applied += 'NVIDIA MidGfxPreemption = 0'
    Set-ItemProperty -Path $nvg -Name 'RMEdgeLpwrEnable'             -Value 0 -Type DWord -Force | Out-Null
    $applied += 'NVIDIA RMEdgeLpwr = 0'

    # RESIZABLE BAR
    Set-ItemProperty -Path $nvr -Name 'EnableResizableBar' -Value 1 -Type DWord -Force | Out-Null
    $applied += 'NVIDIA ResizableBar = 1'

    return $applied
}


function Apply-AmdGpuTweaks {
    $applied = @()

    $amdPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\AMD'
    if (-not (Test-Path $amdPath)) { New-Item -Path $amdPath -Force | Out-Null }

    # GPU SEMPRE A CLOCK MASSIMO
    Set-ItemProperty -Path $amdPath -Name 'EnableUlps'             -Value 0 -Type DWord -Force | Out-Null
    $applied += 'AMD EnableUlps = 0'
    Set-ItemProperty -Path $amdPath -Name 'PP_SclkDeepSleepDisable' -Value 1 -Type DWord -Force | Out-Null
    $applied += 'AMD SclkDeepSleep = disabled'
    Set-ItemProperty -Path $amdPath -Name 'PowerPlayEnabled'        -Value 0 -Type DWord -Force | Out-Null
    $applied += 'AMD PowerPlayEnabled = 0 (max perf)'
    Set-ItemProperty -Path $amdPath -Name 'PP_ThermalAutoThrottlingEnable' -Value 0 -Type DWord -Force | Out-Null
    $applied += 'AMD ThermalAutoThrottling = 0'

    return $applied
}
function Apply-GpuTweaksAuto {
    $applied = @()
    $vendor = Get-GpuVendor
    $applied += "GPU rilevato: $vendor"
    switch ($vendor) {
        'NVIDIA' { $applied += Apply-NvidiaGpuTweaks }
        'AMD'    { $applied += Apply-AmdGpuTweaks }
        default  { $applied += 'SKIP GPU tweaks: vendor non supportato' }
    }
    return $applied
}

function Apply-PagefileFixed {
    $applied = @()
    try {
        $ram = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1MB
        $ramMB = [int]$ram
        $cs = Get-CimInstance Win32_ComputerSystem
        $cs.AutomaticManagedPagefile = $false
        $cs.Put() | Out-Null
        $pf = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue
        if ($pf) {
            $pf.InitialSize = $ramMB
            $pf.MaximumSize = $ramMB
            $pf.Put() | Out-Null
            $applied += "Pagefile fisso: $ramMB MB"
        } else {
            New-CimInstance -ClassName Win32_PageFileSetting -Property @{Name='C:\pagefile.sys';InitialSize=$ramMB;MaximumSize=$ramMB} | Out-Null
            $applied += "Pagefile creato fisso: $ramMB MB"
        }
    } catch {
        $applied += 'SKIP Pagefile: ' + $_.Exception.Message
    }
    return $applied
}

function Apply-WindowsUpdateDisable {
    $applied = @()
    try {
        Stop-Service -Name 'wuauserv' -Force -ErrorAction SilentlyContinue
        Set-Service -Name 'wuauserv' -StartupType Disabled | Out-Null
        $applied += 'Windows Update disabilitato'
        Stop-Service -Name 'UsoSvc' -Force -ErrorAction SilentlyContinue
        Set-Service -Name 'UsoSvc' -StartupType Disabled | Out-Null
        $applied += 'UsoSvc disabilitato'
        Stop-Service -Name 'DoSvc' -Force -ErrorAction SilentlyContinue
        try {
    Set-Service -Name 'DoSvc' -StartupType Disabled -ErrorAction Stop | Out-Null
    $applied += 'DoSvc disabilitato'
}
catch {
    $applied += "SKIP DoSvc: $($_.Exception.Message)"
}
        $applied += 'Delivery Optimization disabilitato'
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name 'NoAutoUpdate' -Value 1 -Type DWord -Force | Out-Null
        $applied += 'NoAutoUpdate policy = 1'
    } catch {
        $applied += 'SKIP WUpdate: ' + $_.Exception.Message
    }
    return $applied
}

function Apply-TelemetryAdvanced {
    $applied = @()
    $telKeys = @(
        @{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack'; Name='DiagTrackAuthorization'; Value=0 },
        @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name='AllowTelemetry'; Value=0 },
        @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name='DoNotShowFeedbackNotifications'; Value=1 },
        @{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy'; Name='TailoredExperiencesWithDiagnosticDataEnabled'; Value=0 },
        @{ Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy'; Name='TailoredExperiencesWithDiagnosticDataEnabled'; Value=0 },
        @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name='DisableInventory'; Value=1 },
        @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name='DisablePCA'; Value=1 },
        @{ Path='HKLM:\SOFTWARE\Microsoft\SQMClient\Windows'; Name='CEIPEnable'; Value=0 },
        @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\MRT'; Name='DontReportInfectionInformation'; Value=1 },
        @{ Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name='Enabled'; Value=0 },
        @{ Path='HKCU:\SOFTWARE\Microsoft\Input\TIPC'; Name='Enabled'; Value=0 },
        @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization'; Name='RestrictImplicitInkCollection'; Value=1 },
        @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization'; Name='RestrictImplicitTextCollection'; Value=1 },
        @{ Path='HKCU:\SOFTWARE\Microsoft\Personalization\Settings'; Name='AcceptedPrivacyPolicy'; Value=0 },
        @{ Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SettingSync'; Name='SyncPolicy'; Value=5 }
    )
    foreach ($k in $telKeys) {
        try {
            if (-not (Test-Path $k.Path)) { New-Item -Path $k.Path -Force | Out-Null }
            Set-ItemProperty -Path $k.Path -Name $k.Name -Value $k.Value -Type DWord -Force | Out-Null
            $applied += "Telemetria: $($k.Name) = $($k.Value)"
        } catch { $applied += "SKIP $($k.Name)" }
    }
    return $applied
}

function Apply-ETWOff {
    $applied = @()
    $etwSessions = @('DiagLog','Diagtrack-Listener','NOLAAS','WiFiSession')
    foreach ($s in $etwSessions) {
        try {
            & logman.exe stop $s -ets 2>$null | Out-Null
            $applied += "ETW session stopped: $s"
        } catch { $applied += "SKIP ETW $s" }
    }

    $diagPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener'
    try {
        if (Test-Path $diagPath) {
            Set-ItemProperty -Path $diagPath -Name 'Start' -Value 0 -Type DWord -Force | Out-Null
            $applied += 'AutoLogger-Diagtrack disabled'
        }
        else {
            $applied += 'SKIP AutoLogger-Diagtrack path non presente'
        }
    }
    catch {
        $applied += "SKIP AutoLogger-Diagtrack: $($_.Exception.Message)"
    }

    return $applied
}

function Apply-InterruptAffinity {
    $applied = @()
    try {
        $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface } | Select-Object -First 1
        if ($adapter) {
            $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($adapter.DeviceID)\Device Parameters\Interrupt Management\Affinity Policy"
            if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
            Set-ItemProperty -Path $path -Name 'DevicePolicy' -Value 4 -Type DWord -Force | Out-Null
            Set-ItemProperty -Path $path -Name 'AssignmentSetOverride' -Value ([byte[]](0x04)) -Type Binary -Force | Out-Null
            $applied += "IRQ affinity pinned su core 2: $($adapter.Name)"
        }
    } catch { $applied += 'SKIP Interrupt Affinity: ' + $_.Exception.Message }
    return $applied
}

function Apply-ShaderCacheClean {
    $applied = @()
    $paths = @(
        "$env:LOCALAPPDATA\NVIDIA\DXCache",
        "$env:LOCALAPPDATA\NVIDIA\GLCache",
        "$env:LOCALAPPDATA\D3DSCache",
        "$env:LOCALAPPDATA\AMD\DxCache",
        "$env:APPDATA\NVIDIA\ComputeCache"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Remove-Item -Path "$p\*" -Recurse -Force -ErrorAction SilentlyContinue
            $applied += "Shader cache pulita: $p"
        }
    }
    return $applied
}

function Apply-DwmFrameInterval {
    $applied = @()
    try {
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex' -Value 0xffffffff -Type DWord -Force | Out-Null
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'SystemResponsiveness' -Value 0 -Type DWord -Force | Out-Null
        Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\DWMApps' -Name 'dwmframeinterval' -Value 6 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
        $applied += 'DWM frame interval ottimizzato'
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR LATENCYHINTPERF1 99 2>$null | Out-Null
        $applied += 'CPU latency hint perf = 99'
    } catch { $applied += 'SKIP DWM frame: ' + $_.Exception.Message }
    return $applied
}

function Apply-CoreParkingOff {
    $applied = @()
    try {
        $paths = @(
            'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583',
            'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\ea062031-0e34-4ff1-9b6d-eb1059334028'
        )
        foreach ($p in $paths) {
            if (Test-Path $p) {
                Set-ItemProperty -Path $p -Name 'Attributes' -Value 2 -Type DWord -Force | Out-Null
                $applied += "Core Parking policy unlocked"
            }
        }
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100 2>$null | Out-Null
        powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100 2>$null | Out-Null
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMAXCORES 100 2>$null | Out-Null
        $applied += 'Core Parking: min=100% max=100%'
    } catch { $applied += 'SKIP Core Parking: ' + $_.Exception.Message }
    return $applied
}

function Apply-SpectreMitigationsOff {
    $applied = @()
    try {
        bcdedit /set nx AlwaysOff 2>$null | Out-Null
        $applied += 'BCD nx = AlwaysOff'
        bcdedit /set bootmenupolicy Legacy 2>$null | Out-Null
        $applied += 'BCD bootmenupolicy = Legacy'
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'FeatureSettingsOverride' -Value 3 -Type DWord -Force | Out-Null
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'FeatureSettingsOverrideMask' -Value 3 -Type DWord -Force | Out-Null
        $applied += 'Spectre/Meltdown mitigations OFF'
    } catch { $applied += 'SKIP Spectre: ' + $_.Exception.Message }
    return $applied
}

function Apply-RSSQueuePinning {
    $applied = @()
    try {
        $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface } | Select-Object -First 1
        if ($adapter) {
            Set-NetAdapterRSS -Name $adapter.Name -NumberOfReceiveQueues 4 -MaxQueuesPerCore 1 -ErrorAction SilentlyContinue | Out-Null
            $applied += "RSS queue pinning (4 queues) su $($adapter.Name)"
        }
    } catch { $applied += 'SKIP RSS: ' + $_.Exception.Message }
    return $applied
}

function Apply-NVMeLatency {
    $applied = @()
    $keys = @('storsvc','StorAHCI','storahci','storport')
    foreach ($k in $keys) {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\$k"
        if (Test-Path $path) {
            Set-ItemProperty -Path $path -Name 'Start' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
            $applied += "$k Start = 0"
        }
    }
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\storport\Parameters' -Name 'EnableIdlePowerManagement' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
    $applied += 'StorPort IdlePowerManagement = 0'
    return $applied
}

function Apply-DPCTweaks {
    $applied = @()
    try {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'IRQ8Priority' -Value 1 -Type DWord -Force | Out-Null
        $applied += 'IRQ8 priority = 1'
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'IRQ16Priority' -Value 1 -Type DWord -Force | Out-Null
        $applied += 'IRQ16 priority = 1'
        if (-not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\TimedInterruptMiniportDriver')) {
            New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\TimedInterruptMiniportDriver' -Force | Out-Null
        }
        $applied += 'DPC latency tweaks applicati'
    } catch { $applied += 'SKIP DPC: ' + $_.Exception.Message }
    return $applied
}

function Apply-PrefetchOff {
    $applied = @()
    try {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' -Name 'EnablePrefetcher' -Value 0 -Type DWord -Force | Out-Null
        $applied += 'EnablePrefetcher = 0'
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' -Name 'EnableSuperfetch' -Value 0 -Type DWord -Force | Out-Null
        $applied += 'EnableSuperfetch = 0'
    } catch { $applied += 'SKIP Prefetch: ' + $_.Exception.Message }
    return $applied
}

function Apply-TaskOffload {
    $applied = @()
    try {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'DisableTaskOffload' -Value 1 -Type DWord -Force | Out-Null
        $applied += 'DisableTaskOffload = 1'
    } catch { $applied += 'SKIP TaskOffload: ' + $_.Exception.Message }
    return $applied
}

function Set-TimerResolution {
    $applied = @()
    try {
        # Crea un piccolo script che usa winmm per mantenere 1ms
        $timerScript = @'
using System;
using System.Runtime.InteropServices;
class TimerRes {
    [DllImport("winmm.dll")] static extern int timeBeginPeriod(int t);
    static void Main() { timeBeginPeriod(1); Console.WriteLine("Timer 1ms attivo - chiudi questa finestra per ripristinare"); Console.ReadLine(); }
}
'@
        $outPath = Join-Path $env:TEMP 'TedeTimer.cs'
        $exePath = Join-Path $env:TEMP 'TedeTimer.exe'
        Set-Content -Path $outPath -Value $timerScript -Encoding UTF8
        $csc = Get-ChildItem "C:\Windows\Microsoft.NET\Framework64" -Filter csc.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -Last 1
        if ($csc) {
            & $csc.FullName /out:$exePath $outPath 2>$null | Out-Null
            if (Test-Path $exePath) {
                Start-Process -FilePath $exePath -WindowStyle Normal
                $applied += 'TedeTimer.exe avviato (tieni aperto durante il gaming)'
            }
        } else {
            $applied += 'SKIP TedeTimer: .NET compiler non trovato'
        }
    } catch { $applied += 'SKIP Timer: ' + $_.Exception.Message }
    return $applied
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="One Piece Performance Panel"
        Height="770"
        Width="1080"
        WindowStartupLocation="CenterScreen"
        Background="#0B1120"
        Foreground="#F9FAFB">
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="190"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <Border Grid.Column="0" Background="#071626">
            <StackPanel Margin="14">
                <TextBlock Text="TedeTweak"
                           FontSize="22"
                           FontWeight="Bold"
                           Foreground="#F8E7B6"
                           Margin="0,0,0,18"/>

                <Button Name="BtnNavPreset" Content="Crew Routes" Height="36" Margin="0,0,0,8" Background="#3A2416" Foreground="#F7E7C1" BorderBrush="#8A6735"/>
                <Button Name="BtnNavTweaks" Content="Ship Systems" Height="36" Margin="0,0,0,8" Background="#071626" Foreground="#F7E7C1" BorderBrush="#8A6735"/>
                <Button Name="BtnNavInfo" Content="Captain Log" Height="36" Margin="0,0,0,8" Background="#071626" Foreground="#F7E7C1" BorderBrush="#8A6735"/>
            </StackPanel>
        </Border>

        <Grid Grid.Column="1" Margin="14">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <Grid Grid.Row="0" Margin="0,0,0,12">
    <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="220"/>
    </Grid.ColumnDefinitions>

    <Border Grid.Column="0"
            Background="#1A120E"
            BorderBrush="#8F642E"
            BorderThickness="1"
            CornerRadius="12"
            Padding="16"
            Margin="0,0,12,0">
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="64"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <Border Width="52"
                    Height="52"
                    CornerRadius="10"
                    Background="#2A1A12"
                    BorderBrush="#D6A85F"
                    BorderThickness="1"
                    VerticalAlignment="Top">
                <TextBlock Text="☠"
                           FontSize="24"
                           HorizontalAlignment="Center"
                           VerticalAlignment="Center"
                           TextAlignment="Center"
                           Foreground="#F4D28C"
                           Margin="0,9,0,0"/>
            </Border>

            <StackPanel Grid.Column="1" Margin="14,0,0,0">
                <TextBlock Text="TEDETWEAK COMMAND DECK"
                           FontSize="24"
                           FontWeight="Bold"
                           Foreground="#FFF1CC"/>
                <TextBlock Name="TxtModeLabel"
                           Text="Route: EAST BLUE"
                           FontSize="13"
                           Margin="0,4,0,6"
                           Foreground="#C9B28D"/>
                <TextBlock Text="Latency, frametime and 1% low oriented control panel."
                           FontSize="12"
                           Foreground="#A89274"
                           TextWrapping="Wrap"/>
            </StackPanel>
        </Grid>
    </Border>

    <Border Name="ModeChipBorder"
            Grid.Column="1"
            Background="#0D9488"
            BorderBrush="#E6C27A"
            BorderThickness="1"
            CornerRadius="14"
            Padding="16,12"
            VerticalAlignment="Stretch">
        <StackPanel VerticalAlignment="Center">
            <TextBlock Text="ACTIVE GEAR"
                       FontSize="11"
                       FontWeight="SemiBold"
                       Foreground="#FBECC8"
                       HorizontalAlignment="Center"/>
            <TextBlock Name="TxtModeChip"
                       Text="Gear 2"
                       FontSize="18"
                       FontWeight="Bold"
                       Foreground="#FFF8E7"
                       HorizontalAlignment="Center"
                       Margin="0,4,0,0"/>
        </StackPanel>
    </Border>
</Grid>

            <TabControl Name="MainTab" Grid.Row="1" Background="#071626" BorderBrush="#8A6735">
                <TabItem Header="Crew Routes">
                    <Grid Background="#071626" Margin="8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="330"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <StackPanel Grid.Column="0" Margin="0,0,12,0">
                            <Border Background="#241611" BorderBrush="#8F642E" BorderThickness="1" CornerRadius="10" Padding="14" Margin="0,0,0,12">
    <StackPanel>
        <TextBlock Text="Crew Route"
                   FontSize="16"
                   FontWeight="Bold"
                   Foreground="#FFF1CC"
                   Margin="0,0,0,4"/>
        <TextBlock Text="Scegli il profilo di spinta del pannello."
                   FontSize="12"
                   Foreground="#BFA784"
                   Margin="0,0,0,12"/>

        <Border Background="#1D2B29" BorderBrush="#2C8E83" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,8">
            <RadioButton Name="RbSafe"
                         Content="East Blue  •  consigliato"
                         IsChecked="True"
                         Foreground="#EAFBF7"
                         FontWeight="SemiBold"/>
        </Border>

        <Border Background="#331313" BorderBrush="#B33A3A" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,8">
            <RadioButton Name="RbInsane"
                         Content="Yonko Mode  •  tryhard"
                         Foreground="#FFF0F0"
                         FontWeight="SemiBold"/>
        </Border>

        <Border Background="#1B1E24" BorderBrush="#596273" BorderThickness="1" CornerRadius="8" Padding="10">
            <RadioButton Name="RbCustom"
                         Content="Grand Line Custom  •  manuale"
                         Foreground="#E5E7EB"
                         FontWeight="SemiBold"/>
        </Border>
    </StackPanel>
</Border>
                        </StackPanel>

                        <Border Grid.Column="1" Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="14">
                            <StackPanel>
                                <TextBlock Text="Descrizione preset" FontSize="16" FontWeight="Bold" Foreground="#F8E7B6" Margin="0,0,0,8"/>
                                <TextBlock Name="TxtPresetDescription" Text="Competitive Safe: servizi base, debloat safe, power advanced, scheduler, input, USB, memory lite, cleanup pro, storage, display, cache, GPU helper, NIC advanced, overlay killer, validation report e gaming common." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,12"/>
                                <TextBlock Text="EAST BLUE" FontWeight="Bold" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                <TextBlock Text="- servizi base, debloat safe, power advanced, scheduler, input, USB, memory lite, background cleanup safe e gaming common." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,6"/>
                                <TextBlock Text="YONKO MODE" FontWeight="Bold" Foreground="#F7E7C1" Margin="0,4,0,4"/>
                                <TextBlock Text="- aggiunge debloat aggressive, power advanced, scheduler, input, USB, memory aggressive e Fortnite specific." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,6"/>
                                <TextBlock Text="GRAND LINE" FontWeight="Bold" Foreground="#F7E7C1" Margin="0,4,0,4"/>
                                <TextBlock Text="- usa solo le checkbox selezionate nel tab Tweaks, incluso debloat extreme custom." TextWrapping="Wrap" Foreground="#F7E7C1"/>
                            </StackPanel>
                        </Border>
                    </Grid>
                </TabItem>

                <TabItem Header="Ship Systems">
                    <ScrollViewer Background="#071626">
                        <StackPanel Margin="8">
                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Services and Debloat" FontSize="15" FontWeight="Bold" Foreground="#F8E7B6" Margin="0,0,0,4"/>
                                    <TextBlock Text="Servizi Windows e rimozione bloatware selettiva." Foreground="#F7E7C1" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkServicesBase" Content="Services base (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkDebloatSafe" Content="Debloat safe (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkDebloatAggressive" Content="Debloat aggressive (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkDebloatExtreme" Content="Debloat extreme custom (reale)" Foreground="#F7E7C1"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Debloat extreme custom" FontSize="15" FontWeight="Bold" Foreground="#F8E7B6" Margin="0,0,0,4"/>
                                    <TextBlock Text="Seleziona manualmente i pacchetti da rimuovere. Le opzioni sotto vengono usate solo se il toggle Debloat extreme custom e attivo." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,8"/>

                                    <WrapPanel Margin="0,0,0,10">
                                        <Button Name="BtnDebloatRecommended" Content="Select recommended" Width="140" Height="30" Margin="0,0,8,0" Background="#8A6735" Foreground="#F8E7B6" BorderBrush="#374151"/>
                                        <Button Name="BtnDebloatAll" Content="Select all" Width="110" Height="30" Margin="0,0,8,0" Background="#8A6735" Foreground="#F8E7B6" BorderBrush="#374151"/>
                                        <Button Name="BtnDebloatClear" Content="Clear all" Width="110" Height="30" Background="#8A6735" Foreground="#F8E7B6" BorderBrush="#374151"/>
                                    </WrapPanel>

                                    <CheckBox Name="ChkDebloatUsers" Content="Rimuovi per utenti esistenti" IsChecked="True" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkDebloatProvisioned" Content="Rimuovi anche provisioning per nuovi utenti" IsChecked="True" Foreground="#F7E7C1" Margin="0,0,0,10"/>

                                    <UniformGrid Columns="3">
                                        <CheckBox Name="DbClipchamp" Content="Clipchamp" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbBingNews" Content="Bing News" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbGetHelp" Content="Get Help" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbGetStarted" Content="Get Started" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbOfficeHub" Content="Office Hub" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbSolitaire" Content="Solitaire" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbPeople" Content="People" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbSkype" Content="Skype" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbTeams" Content="Teams Consumer" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbXboxTCUI" Content="Xbox TCUI" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbXboxApp" Content="Xbox App" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbXboxGameOverlay" Content="Xbox Game Overlay" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbXboxGamingOverlay" Content="Xbox Gaming Overlay" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbXboxIdentity" Content="Xbox Identity Provider" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbXboxSpeech" Content="Xbox Speech To Text" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbPhoneLink" Content="Phone Link" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbGroove" Content="Groove Music" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbMovies" Content="Movies and TV" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbTodo" Content="To Do" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbFamily" Content="Family" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbQuickAssist" Content="Quick Assist" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbDevHome" Content="Dev Home" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbFeedbackHub" Content="Feedback Hub" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbMaps" Content="Maps" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbCamera" Content="Camera" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbSoundRecorder" Content="Sound Recorder" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbAlarms" Content="Alarms" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                        <CheckBox Name="DbMailCalendar" Content="Mail and Calendar" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    </UniformGrid>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
    <StackPanel>
        <TextBlock Text="Engine Core" FontSize="15" FontWeight="Bold" Foreground="#F8E7B6" Margin="0,0,0,4"/>
        <TextBlock Text="Blocchi per input delay, reattività e frametime più stabili." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,8"/>

        <CheckBox Name="ChkPowerAdvanced" Content="Power advanced reale" Foreground="#F7E7C1" Margin="0,0,0,4"/>
        <CheckBox Name="ChkScheduler" Content="Scheduler MMCSS reale" Foreground="#F7E7C1" Margin="0,0,0,4"/>
        <CheckBox Name="ChkInput" Content="Input tweaks reale" Foreground="#F7E7C1" Margin="0,0,0,4"/>
        <CheckBox Name="ChkUsb" Content="USB low latency reale" Foreground="#F7E7C1" Margin="0,0,0,4"/>
        <CheckBox Name="ChkGpuTweaks" Content="GPU driver tweaks NVIDIA/AMD" Foreground="#F7E7C1" Margin="0,0,0,4"/>
        <CheckBox Name="ChkPagefile" Content="Pagefile fisso RAM size" Foreground="#F7E7C1" Margin="0,0,0,4"/>
        <CheckBox Name="ChkWUpdateOff" Content="Windows Update OFF" Foreground="#F7E7C1" Margin="0,0,0,4"/>
        <CheckBox Name="ChkETWOff" Content="ETW Telemetry OFF" Foreground="#F7E7C1" Margin="0,0,0,4"/>
        <CheckBox Name="ChkShaderClean" Content="Shader cache cleanup" Foreground="#F7E7C1" Margin="0,0,0,4"/>
        <CheckBox Name="ChkTimerRes" Content="Timer Resolution 1ms" Foreground="#F7E7C1" Margin="0,0,0,4"/>
        <CheckBox Name="ChkSpectreOff" Content="Spectre/Meltdown OFF RISCHIO" Foreground="#F7E7C1" Margin="0,0,0,4"/>
    </StackPanel>
</Border>
                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Memory" FontSize="15" FontWeight="Bold" Foreground="#F8E7B6" Margin="0,0,0,4"/>
                                    <TextBlock Text="Tweak memoria lite o aggressivi." Foreground="#F7E7C1" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkMemoryLite" Content="Memory lite (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkMemoryAggressive" Content="Memory aggressive (reale)" Foreground="#F7E7C1"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Background cleanup" FontSize="15" FontWeight="Bold" Foreground="#F8E7B6" Margin="0,0,0,4"/>
                                    <TextBlock Text="Riduce esperienze Windows e processi non essenziali senza toccare app utente comuni." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkCleanupSafe" Content="Background cleanup safe (reale)" Foreground="#F7E7C1"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="System finish" FontSize="15" FontWeight="Bold" Foreground="#F8E7B6" Margin="0,0,0,4"/>
                                    <TextBlock Text="Storage, overlay display, pulizia cache e cleanup processi Windows non essenziali." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkStorage" Content="Storage advanced (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkDisplay" Content="Display pipeline (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkCache" Content="Cache cleanup (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkCleanupPro" Content="Process cleanup safe pro (reale)" Foreground="#F7E7C1"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Network and timer" FontSize="15" FontWeight="Bold" Foreground="#F8E7B6" Margin="0,0,0,4"/>
                                    <TextBlock Text="Tuning rete competitiva, MSI mode e timer di boot." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkNetworkCommon" Content="Network common (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkNetworkAdapter" Content="Network adapter mode (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkMSI" Content="MSI mode (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkBCD" Content="BCD / timer tweaks (reale)" Foreground="#F7E7C1"/>
                                    <CheckBox Name="ChkDnsOnly" Content="DNS only (Cloudflare)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkTcpLatency" Content="TCP low latency only" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkNduOff" Content="NDU off only" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Cannons and GPU" FontSize="15" FontWeight="Bold" Foreground="#F8E7B6" Margin="0,0,0,4"/>
                                    <TextBlock Text="Vendor-specific helper tuning e tweak generici per game exe." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkGpuVendor" Content="GPU vendor-specific helper (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkGameExeGeneric" Content="Game EXE generic flags (reale)" Foreground="#F7E7C1" Margin="0,0,0,6"/>
                                    <TextBlock Text="Percorso game exe" Foreground="#D9C7A0" Margin="0,4,0,4"/>
                                    <TextBox Name="TxtGameExePath" Text="" Background="#3A2416" Foreground="#F8E7B6" BorderBrush="#9A7A49" Padding="8"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Captain Optional" FontSize="15" FontWeight="Bold" Foreground="#F8E7B6" Margin="0,0,0,4"/>
                                    <TextBlock Text="NIC fine tuning, overlay cleanup, security profile e driver/vendor cleanup." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkNicAdvanced" Content="NIC advanced fine tuning (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkOverlayKiller" Content="Overlay killer (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkSecurityOptional" Content="Security optional profile (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkVendorCleanup" Content="Vendor cleanup / telemetry light (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkValidationReport" Content="Validation report (reale)" Foreground="#F7E7C1"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12">
                                <StackPanel>
                                    <TextBlock Text="Battle Mode" FontSize="15" FontWeight="Bold" Foreground="#F8E7B6" Margin="0,0,0,4"/>
                                    <TextBlock Text="GameDVR, Game Mode, HAGS e Fortnite." Foreground="#F7E7C1" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkGaming" Content="Gaming common (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkFortnite" Content="Fortnite specific (reale)" Foreground="#F7E7C1"/>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </ScrollViewer>
                </TabItem>

                <TabItem Header="Captain Log">
    <Grid Background="#14100C" Margin="8">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <Border Background="#241611"
                BorderBrush="#8F642E"
                BorderThickness="1"
                CornerRadius="10"
                Padding="16"
                Margin="0,0,0,12">
            <StackPanel>
                <TextBlock Text="Captain Log"
                           FontSize="18"
                           FontWeight="Bold"
                           Foreground="#FFF1CC"/>
                <TextBlock Text="Stato attuale del preset, warning attivi e focus competitivo del pannello."
                           Margin="0,6,0,0"
                           Foreground="#C9B28D"
                           TextWrapping="Wrap"/>
            </StackPanel>
        </Border>

        <Grid Grid.Row="1">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <Border Grid.Row="0" Grid.Column="0" Background="#1F1612" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="10" Padding="14" Margin="0,0,10,10">
                <StackPanel>
                    <TextBlock Text="Hardware Profile" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC"/>
                    <TextBlock Name="TxtHardwareInfo" Text="Analisi hardware in attesa..." Foreground="#F7E7C1" Margin="0,8,0,0" TextWrapping="Wrap"/>
                </StackPanel>
            </Border>

            <Border Grid.Row="0" Grid.Column="1" Background="#201511" BorderBrush="#B45309" BorderThickness="1" CornerRadius="10" Padding="14" Margin="0,0,0,10">
                <StackPanel>
                    <TextBlock Text="Warnings" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC"/>
                    <TextBlock Name="TxtWarningsInfo" Text="Nessun warning importante." Foreground="#F7E7C1" Margin="0,8,0,0" TextWrapping="Wrap"/>
                </StackPanel>
            </Border>

            <Border Grid.Row="1" Grid.Column="0" Background="#13211D" BorderBrush="#0D9488" BorderThickness="1" CornerRadius="10" Padding="14" Margin="0,0,10,0">
                <StackPanel>
                    <TextBlock Text="Risk Level" FontSize="15" FontWeight="Bold" Foreground="#ECFDF5"/>
                    <TextBlock Name="TxtRiskLevel" Text="SAFE" FontSize="18" FontWeight="Bold" Foreground="#99F6E4" Margin="0,8,0,0"/>
                </StackPanel>
            </Border>

            <Border Grid.Row="1" Grid.Column="1" Background="#221717" BorderBrush="#DC2626" BorderThickness="1" CornerRadius="10" Padding="14">
                <StackPanel>
                    <TextBlock Text="Reboot Impact" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC"/>
                    <TextBlock Name="TxtRebootInfo" Text="Riavvio consigliato dopo tweak di rete, timer o sicurezza." Foreground="#F7E7C1" Margin="0,8,0,0" TextWrapping="Wrap"/>
                </StackPanel>
            </Border>
        </Grid>
    </Grid>
</TabItem>
            </TabControl>

            <Grid Grid.Row="2" Margin="0,10,0,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Name="TxtStatus" Grid.Column="0" Text="Pronto." VerticalAlignment="Center" Foreground="#9CA3AF"/>
                <Button Name="BtnApply" Grid.Column="1" Content="Set Sail / Apply Tweaks" Width="160" Height="36" Background="#B63A2B" Foreground="#F8E7B6" BorderBrush="#B63A2B"/>
            </Grid>
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
$ChkGpuTweaks = $window.FindName('ChkGpuTweaks')
$ChkPagefile = $window.FindName('ChkPagefile')
$ChkWUpdateOff = $window.FindName('ChkWUpdateOff')
$ChkETWOff = $window.FindName('ChkETWOff')
$ChkShaderClean = $window.FindName('ChkShaderClean')
$ChkTimerRes = $window.FindName('ChkTimerRes')
$ChkSpectreOff = $window.FindName('ChkSpectreOff')
$TxtModeLabel = $window.FindName('TxtModeLabel')
$TxtModeChip = $window.FindName('TxtModeChip')
$ModeChipBorder = $window.FindName('ModeChipBorder')
$TxtPresetDescription = $window.FindName('TxtPresetDescription')
$TxtStatus = $window.FindName('TxtStatus')
$BtnApply = $window.FindName('BtnApply')
$TxtWarningsInfo = $window.FindName('TxtWarningsInfo')
$TxtRebootInfo   = $window.FindName('TxtRebootInfo')

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

$TxtHardwareInfo = $window.FindName('TxtHardwareInfo')
$TxtWarningsInfo = $window.FindName('TxtWarningsInfo')
$TxtRiskLevel = $window.FindName('TxtRiskLevel')
$TxtRebootInfo = $window.FindName('TxtRebootInfo')

$ChkDnsOnly              = $window.FindName('ChkDnsOnly')
$ChkTcpLatency           = $window.FindName('ChkTcpLatency')
$ChkNduOff               = $window.FindName('ChkNduOff')

$RefreshCaptainLog = {
    Update-TedeDynamicInfo `
        -HardwareBlock $TxtHardwareInfo `
        -WarningsBlock $TxtWarningsInfo `
        -RiskBlock $TxtRiskLevel `
        -RebootBlock $TxtRebootInfo
}

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
        $TxtModeLabel.Text = 'Luffy: GEAR 2'
        $TxtModeChip.Text = 'Gear 2'
        $ModeChipBorder.Background = '#0D9488'
        $TxtPresetDescription.Text = 'Gear 2: servizi base, debloat safe, power advanced, scheduler, input, USB, memory lite, cleanup pro, storage, display, cache, GPU helper, NIC advanced, overlay killer, validation report e gaming common.'
    }
    elseif ($RbInsane.IsChecked) {
        $TxtModeLabel.Text = 'Luffy: JOY BOY'
        $TxtModeChip.Text = 'JOY BOY'
        $ModeChipBorder.Background = '#DC2626'
        $TxtPresetDescription.Text = 'Joy Boy: aggiunge debloat aggressive, memory aggressive, security optional, vendor cleanup, game/network advanced, MSI, BCD, validation report e Fortnite specific.'
    }
    else {
        $TxtModeLabel.Text = 'Route: GRAND LINE'
        $TxtModeChip.Text = 'GRAND LINE'
        $ModeChipBorder.Background = '#4B5563'
        $TxtPresetDescription.Text = 'Grand Line: applica solo i gruppi selezionati nel tab Tweaks, incluso debloat extreme custom.'
    }
}

function Get-TedeCurrentPresetName {
    if ($RbSafe.IsChecked)   { return 'GEAR 2' }
    if ($RbInsane.IsChecked) { return 'JOY BOY' }
    return 'GRAND LINE'
}

$sel = Get-TedeSelectedBlocks -ChkDebloatExtreme $ChkDebloatExtreme -ChkSecurityOptional $ChkSecurityOptional -ChkBCD $ChkBCD -ChkMSI $ChkMSI -ChkMemoryAggressive $ChkMemoryAggressive
$riskNow = Get-TedeRiskLevel -HasExtreme $sel.HasExtreme -HasSecurity $sel.HasSecurity -HasBCD $sel.HasBCD -HasMSI $sel.HasMSI -HasMemoryAggressive $sel.HasMemoryAggressive
$warnNow = Get-TedeWarningMessages -HasExtreme $sel.HasExtreme -HasSecurity $sel.HasSecurity -HasBCD $sel.HasBCD -HasMSI $sel.HasMSI -HasMemoryAggressive $sel.HasMemoryAggressive
Update-TedeDynamicInfo `
    -HardwareBlock $TxtHardwareInfo `
    -WarningsBlock $TxtWarningsInfo `
    -RiskBlock $TxtRiskLevel `
    -RebootBlock $TxtRebootInfo

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
    $TxtStatus.Text = 'Preset GEAR 2 caricato.'


    $applied += Apply-GpuTweaksAuto
    $applied += Apply-PagefileFixed
    $applied += Apply-WindowsUpdateDisable
    $applied += Apply-TelemetryAdvanced
    $applied += Apply-PrefetchOff
    $applied += Apply-NVMeLatency
    $applied += Apply-DPCTweaks
    $applied += Apply-TaskOffload
}

function Set-InsanePreset {
    $ChkServicesBase.IsChecked = $true

    $ChkDebloatSafe.IsChecked = $false
    $ChkDebloatAggressive.IsChecked = $false
    $ChkDebloatExtreme.IsChecked = $true
    $ChkDebloatUsers.IsChecked = $true
    $ChkDebloatProvisioned.IsChecked = $true

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
    $ChkDnsOnly.IsChecked = $true
    $ChkTcpLatency.IsChecked = $true
    $ChkNduOff.IsChecked = $true
    $ChkMSI.IsChecked = $true
    $ChkBCD.IsChecked = $true

    $ChkGpuVendor.IsChecked = $true
    $ChkGameExeGeneric.IsChecked = $true
    $ChkNicAdvanced.IsChecked = $true
    $ChkOverlayKiller.IsChecked = $true
    $ChkSecurityOptional.IsChecked = $true
    $ChkVendorCleanup.IsChecked = $true
    $ChkValidationReport.IsChecked = $true

    $ChkGaming.IsChecked = $true
    $ChkFortnite.IsChecked = $true

    Set-DebloatSelection -Items @($DebloatBoxes.Keys)

    $TxtStatus.Text = 'Preset JOY BOY caricato: full send.'
}


function Set-CustomPreset {
    $ChkServicesBase.IsChecked        = $false
    $ChkDebloatSafe.IsChecked         = $false
    $ChkDebloatAggressive.IsChecked   = $false
    $ChkDebloatExtreme.IsChecked      = $false

    $ChkPowerAdvanced.IsChecked       = $false
    $ChkScheduler.IsChecked           = $false
    $ChkInput.IsChecked               = $false
    $ChkUsb.IsChecked                 = $false

    $ChkMemoryLite.IsChecked          = $false
    $ChkMemoryAggressive.IsChecked    = $false

    $ChkCleanupSafe.IsChecked         = $false
    $ChkStorage.IsChecked             = $false
    $ChkDisplay.IsChecked             = $false
    $ChkCache.IsChecked               = $false
    $ChkCleanupPro.IsChecked          = $false

    $ChkNetworkCommon.IsChecked       = $false
    $ChkNetworkAdapter.IsChecked      = $false
    $ChkMSI.IsChecked                 = $false
    $ChkBCD.IsChecked                 = $false

    $ChkGpuVendor.IsChecked           = $false
    $ChkGameExeGeneric.IsChecked      = $false
    $ChkNicAdvanced.IsChecked         = $false
    $ChkOverlayKiller.IsChecked       = $false
    $ChkSecurityOptional.IsChecked    = $false
    $ChkVendorCleanup.IsChecked       = $false
    $ChkValidationReport.IsChecked    = $false

    $ChkGaming.IsChecked              = $false
    $ChkFortnite.IsChecked            = $false

    $ChkDebloatUsers.IsChecked        = $true
    $ChkDebloatProvisioned.IsChecked  = $true

    $ChkDnsOnly.IsChecked    = $false
    $ChkTcpLatency.IsChecked = $false
    $ChkNduOff.IsChecked     = $false
    


    if ($TxtGameExePath) {
        $TxtGameExePath.Text = ""
    }

    Set-DebloatSelection -Items @()
    $TxtStatus.Text = "Modalita GRAND LINE CUSTOM attiva. Modifica le checkbox a piacere."
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

$BtnDebloatRecommended.Add_Click({ Set-DebloatSelection -Items $RecommendedDebloat; $TxtStatus.Text = 'Debloat consigliato selezionato.' })
$BtnDebloatAll.Add_Click({ Set-DebloatSelection -Items @($DebloatBoxes.Keys); $TxtStatus.Text = 'Tutti i debloat selezionati.'
    Update-TedeDynamicInfo `
    -HardwareBlock $TxtHardwareInfo `
    -WarningsBlock $TxtWarningsInfo `
    -RiskBlock $TxtRiskLevel `
    -RebootBlock $TxtRebootInfo -RiskBlock $TxtRiskLevel -CmbPreset $CmbPreset -ChkDebloatAggressive $ChkDebloatAggressive -ChkDebloatExtreme $ChkDebloatExtreme -ChkNetworkCommon $ChkNetworkCommon -ChkNetworkAdapter $ChkNetworkAdapter -ChkMSI $ChkMSI -ChkBCD $ChkBCD -ChkCleanupPro $ChkCleanupPro })
$BtnDebloatClear.Add_Click({ Set-DebloatSelection -Items @(); $TxtStatus.Text = 'Debloat custom pulito.'
    Update-TedeDynamicInfo `
    -HardwareBlock $TxtHardwareInfo `
    -WarningsBlock $TxtWarningsInfo `
    -RiskBlock $TxtRiskLevel `
    -RebootBlock $TxtRebootInfo -RiskBlock $TxtRiskLevel -CmbPreset $CmbPreset -ChkDebloatAggressive $ChkDebloatAggressive -ChkDebloatExtreme $ChkDebloatExtreme -ChkNetworkCommon $ChkNetworkCommon -ChkNetworkAdapter $ChkNetworkAdapter -ChkMSI $ChkMSI -ChkBCD $ChkBCD -ChkCleanupPro $ChkCleanupPro })

if ($BtnRestoreBackup) {
    $BtnRestoreBackup.Add_Click({
        Ensure-RunAsAdmin
        Initialize-TedeWorkspace
        $items = Restore-LatestTedeBackup
        foreach ($entry in $items) { Write-TedeLog $entry 'RESTORE' }

        if ($TxtOutput) {
            $TxtOutput.Text = ($items -join [Environment]::NewLine)
        }
        elseif ($TxtStatus) {
            $TxtStatus.Text = 'Restore completato. Controlla log e backup.'
        }
    })
}

if ($BtnRestoreBackup) {
    $BtnRestoreBackup.Add_Click({
        Ensure-RunAsAdmin
        Initialize-TedeWorkspace
        $items = Restore-LatestTedeBackup
        foreach ($entry in $items) { Write-TedeLog $entry 'RESTORE' }

        if ($TxtOutput) {
            $TxtOutput.Text = ($items -join [Environment]::NewLine)
        }
        elseif ($TxtStatus) {
            $TxtStatus.Text = 'Restore completato. Controlla il log/output.'
        }
    })
}

$sel = Get-TedeSelectedBlocks -ChkDebloatExtreme $ChkDebloatExtreme -ChkSecurityOptional $ChkSecurityOptional -ChkBCD $ChkBCD -ChkMSI $ChkMSI -ChkMemoryAggressive $ChkMemoryAggressive
$riskNow = Get-TedeRiskLevel -HasExtreme $sel.HasExtreme -HasSecurity $sel.HasSecurity -HasBCD $sel.HasBCD -HasMSI $sel.HasMSI -HasMemoryAggressive $sel.HasMemoryAggressive
$warnNow = Get-TedeWarningMessages -HasExtreme $sel.HasExtreme -HasSecurity $sel.HasSecurity -HasBCD $sel.HasBCD -HasMSI $sel.HasMSI -HasMemoryAggressive $sel.HasMemoryAggressive

if (-not (Confirm-TedeSensitiveSelection -RiskText $riskNow -WarningText $warnNow)) {
    $TxtStatus.Text = 'Operazione annullata dall''utente.'
    return
}

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
    if ($ChkDnsOnly -and $ChkDnsOnly.IsChecked) {
    $mode = 'LAN'
    if ($window.FindName('CmbNetMode').SelectedIndex -eq 1) { $mode = 'Wi-Fi' }
    foreach ($item in (Apply-DnsOnly -Mode $mode)) { $done.Add($item) }
}

if ($ChkTcpLatency -and $ChkTcpLatency.IsChecked) {
    foreach ($item in (Apply-TcpLatencyOnly)) { $done.Add($item) }
}

if ($ChkNduOff -and $ChkNduOff.IsChecked) {
    foreach ($item in (Apply-NduOffOnly)) { $done.Add($item) }
}

if ($ChkDnsOnly.IsChecked) { $selected.Add('DNS only') }
if ($ChkTcpLatency.IsChecked) { $selected.Add('TCP latency only') }
if ($ChkNduOff.IsChecked) { $selected.Add('NDU off only') }

    $riskNow = Get-TedeRiskLevel -HasExtreme #([bool]$ChkDebloatExtreme.IsChecked) -HasBCD ([bool]$ChkBCD.IsChecked) -HasMSI ([bool]$ChkMSI.IsChecked) -HasNetwork ([bool]($ChkNetworkCommon.IsChecked -or $ChkNetworkAdapter.IsChecked -or $ChkNicAdvanced.IsChecked)) -HasAggressiveDebloat ([bool]$ChkDebloatAggressive.IsChecked) -HasCleanup ([bool]($ChkCleanupPro.IsChecked -or $ChkOverlayKiller.IsChecked))
    $warnNow = Get-TedeWarningMessages -HasExtreme #([bool]$ChkDebloatExtreme.IsChecked) -HasBCD ([bool]$ChkBCD.IsChecked) -HasMSI ([bool]$ChkMSI.IsChecked) -HasNetwork ([bool]($ChkNetworkCommon.IsChecked -or $ChkNetworkAdapter.IsChecked -or $ChkNicAdvanced.IsChecked)) -HasAggressiveDebloat ([bool]$ChkDebloatAggressive.IsChecked) -HasCleanup ([bool]($ChkCleanupPro.IsChecked -or $ChkOverlayKiller.IsChecked))
    #if (-not (Confirm-TedeSensitiveSelection -RiskText $riskNow -WarningText $warnNow)) {
       #$TxtStatus.Text = "Applicazione annullata dall'utente."
        #return
    #}

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

$sel = Get-TedeSelectedBlocks -ChkDebloatExtreme $ChkDebloatExtreme -ChkSecurityOptional $ChkSecurityOptional -ChkBCD $ChkBCD -ChkMSI $ChkMSI -ChkMemoryAggressive $ChkMemoryAggressive
$riskNow = Get-TedeRiskLevel -HasExtreme $sel.HasExtreme -HasSecurity $sel.HasSecurity -HasBCD $sel.HasBCD -HasMSI $sel.HasMSI -HasMemoryAggressive $sel.HasMemoryAggressive
$warnNow = Get-TedeWarningMessages -HasExtreme $sel.HasExtreme -HasSecurity $sel.HasSecurity -HasBCD $sel.HasBCD -HasMSI $sel.HasMSI -HasMemoryAggressive $sel.HasMemoryAggressive
Update-TedeDynamicInfo `
    -HardwareBlock $TxtHardwareInfo `
    -WarningsBlock $TxtWarningsInfo `
    -RiskBlock $TxtRiskLevel `
    -RebootBlock $TxtRebootInfo-RebootBlock $TxtRebootInfo -RiskText $riskNow -WarningsText $warnNow

$null = $window.ShowDialog()
