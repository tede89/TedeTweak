Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# =========================================================
# CORE
# =========================================================

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

# =========================================================
# WORKSPACE / LOG / BACKUP
# =========================================================

$script:TedeWorkspaceInitialized = $false
$script:TedeDataRoot = $null
$script:TedeBackupRoot = $null
$script:TedeLogRoot = $null
$script:TedeCurrentLog = $null

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
    $line = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] [' + $Level + '] ' + $Message
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

    $items = New-Object System.Collections.Generic.List[string]
    $items.Add('Cartella backup: ' + $backupDir)

    foreach ($pair in @(
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; File = 'memory-management.reg' },
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl'; File = 'priority-control.reg' },
        @{ Path = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; File = 'multimedia-systemprofile.reg' },
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; File = 'tcpip-parameters.reg' },
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Services\Ndu'; File = 'ndu.reg' },
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; File = 'session-power.reg' },
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\Power'; File = 'power.reg' },
        @{ Path = 'HKCU\Control Panel\Mouse'; File = 'hkcu-mouse.reg' },
        @{ Path = 'HKCU\Control Panel\Keyboard'; File = 'hkcu-keyboard.reg' },
        @{ Path = 'HKCU\Software\Microsoft\GameBar'; File = 'hkcu-gamebar.reg' }
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

function Open-TedePath {
    param([string]$Path)
    try {
        if (Test-Path $Path) {
            Start-Process explorer.exe $Path | Out-Null
        }
    }
    catch { }
}

# =========================================================
# DETECTION / INFO
# =========================================================

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

function Get-TedeHardwareProfile {
    $cpu = 'Unknown CPU'
    $ram = 'Unknown RAM'
    $gpu = 'Unknown GPU'

    try {
        $cpuObj = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cpuObj) { $cpu = $cpuObj.Name.Trim() }
    } catch { }

    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($cs -and $cs.TotalPhysicalMemory) {
            $ramGb = [Math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
            $ram = $ramGb.ToString() + ' GB'
        }
    } catch { }

    try {
        $gpuObj = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name } | Select-Object -First 1
        if ($gpuObj) { $gpu = $gpuObj.Name.Trim() }
    } catch { }

    return @(
        'CPU: ' + $cpu,
        'RAM: ' + $ram,
        'GPU: ' + $gpu
    )
}

function Get-ActiveTedeAdapter {
    param([string]$Mode)

    try {
        if ($Mode -eq 'Wi-Fi') {
            return Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
                $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN|802.11'
            } | Select-Object -First 1
        }

        return Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $_.Status -eq 'Up' -and $_.HardwareInterface -eq $true -and $_.InterfaceDescription -notmatch 'Wi-?Fi|Wireless|WLAN|802.11'
        } | Select-Object -First 1
    }
    catch {
        return $null
    }
}

function Get-TedeRiskLevel {
    param(
        [bool]$HasAggressive,
        [bool]$HasBCD,
        [bool]$HasMSI,
        [bool]$HasSecurity,
        [bool]$HasExtremeDebloat
    )

    $score = 0
    if ($HasAggressive) { $score += 1 }
    if ($HasBCD) { $score += 2 }
    if ($HasMSI) { $score += 2 }
    if ($HasSecurity) { $score += 2 }
    if ($HasExtremeDebloat) { $score += 2 }

    if ($score -ge 6) { return 'ALTO' }
    if ($score -ge 3) { return 'MEDIO' }
    return 'BASSO'
}

function Confirm-TedeSensitiveSelection {
    param(
        [string]$RiskText,
        [string[]]$Warnings
    )

    if ($RiskText -eq 'BASSO') { return $true }

    $msg = @()
    $msg += 'Hai selezionato tweak con rischio ' + $RiskText + '.'
    $msg += ''
    foreach ($w in $Warnings) { $msg += '- ' + $w }
    $msg += ''
    $msg += 'Continuare?'

    $res = [System.Windows.MessageBox]::Show(($msg -join [Environment]::NewLine), 'Conferma tweak sensibili', 'YesNo', 'Warning')
    return ($res -eq 'Yes')
}

# =========================================================
# DEBLOAT
# =========================================================

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

    return $result
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

# =========================================================
# TWEAK MODULES
# =========================================================

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

    foreach ($name in @('Widgets','WidgetService','GameBar','GameBarFTServer','XboxPcAppFT')) {
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
    foreach ($proc in @(
        'Widgets',
        'WidgetService',
        'GameBar',
        'GameBarFTServer',
        'PhoneExperienceHost',
        'YourPhone',
        'MicrosoftEdgeWebView2',
        'TextInputHost',
        'LockApp'
    )) {
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
            if ($null -eq $adapter) { return @('SKIP nessun Wi-Fi attivo') }

            netsh interface ip set dns name="$($adapter.Name)" static 1.1.1.1 primary | Out-Null
            netsh interface ip add dns name="$($adapter.Name)" 1.0.0.1 index=2 | Out-Null
            $applied += 'DNS Cloudflare su Wi-Fi: ' + $adapter.Name

            try { Set-NetAdapterPowerManagement -Name $adapter.Name -AllowComputerToTurnOffDevice Disabled -ErrorAction SilentlyContinue; $applied += 'Power management off: ' + $adapter.Name } catch { $applied += 'SKIP power management Wi-Fi' }

            foreach ($pair in @(
                @('Preferred Band','Prefer 5GHz Band'),
                @('Transmit Power','Highest'),
                @('Roaming Aggressiveness','1. Lowest')
            )) {
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
            if ($null -eq $adapter) { return @('SKIP nessuna LAN attiva') }

            netsh interface ip set dns name="$($adapter.Name)" static 1.1.1.1 primary | Out-Null
            netsh interface ip add dns name="$($adapter.Name)" 1.0.0.1 index=2 | Out-Null
            $applied += 'DNS Cloudflare su LAN: ' + $adapter.Name

            try { Set-NetAdapterPowerManagement -Name $adapter.Name -AllowComputerToTurnOffDevice Disabled -ErrorAction SilentlyContinue; $applied += 'Power management off: ' + $adapter.Name } catch { $applied += 'SKIP power management LAN' }

            foreach ($prop in @('Interrupt Moderation','Energy-Efficient Ethernet','Green Ethernet','Flow Control')) {
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
        default {
            $applied += 'SKIP vendor-specific: GPU non riconosciuta'
        }
    }

    return $applied
}

function Apply-GameExeGeneric {
    param([string]$ExePath)

    if ([string]::IsNullOrWhiteSpace($ExePath)) {
        return @('SKIP game exe generic: percorso non inserito')
    }
    if (-not (Test-Path $ExePath)) {
        return @('SKIP game exe generic: file non trovato -> ' + $ExePath)
    }

    Set-RegString -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -Name $ExePath -Value '~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE'
    return @(
        'AppCompat Flags impostati per: ' + $ExePath,
        'Disable Fullscreen Optimizations + High DPI override applicati'
    )
}

function Apply-NicAdvancedTuning {
    param([string]$Mode)

    $applied = @()
    $adapter = Get-ActiveTedeAdapter -Mode $Mode
    if ($null -eq $adapter) { return @('SKIP NIC advanced: nessun adapter ' + $Mode + ' attivo') }

    $applied += 'NIC advanced su: ' + $adapter.Name

    foreach ($prop in @(
        'Interrupt Moderation',
        'Flow Control',
        'Energy-Efficient Ethernet',
        'Green Ethernet',
        'Jumbo Packet',
        'Large Send Offload v2 (IPv4)',
        'Large Send Offload v2 (IPv6)',
        'IPv4 Checksum Offload',
        'TCP Checksum Offload (IPv4)',
        'TCP Checksum Offload (IPv6)',
        'UDP Checksum Offload (IPv4)',
        'UDP Checksum Offload (IPv6)'
    )) {
        try {
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $prop -DisplayValue 'Disabled' -NoRestart -ErrorAction SilentlyContinue
            $applied += $prop + ' = Disabled'
        }
        catch {
            $applied += 'SKIP ' + $prop
        }
    }

    foreach ($pair in @(
        @('Receive Buffers','2048'),
        @('Transmit Buffers','1024')
    )) {
        try {
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $pair[0] -DisplayValue $pair[1] -NoRestart -ErrorAction SilentlyContinue
            $applied += $pair[0] + ' = ' + $pair[1]
        }
        catch {
            $applied += 'SKIP ' + $pair[0]
        }
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
        default {
            $applied += 'SKIP vendor cleanup: GPU non riconosciuta'
        }
    }

    return $applied
}

function New-TedeValidationReport {
    Initialize-TedeWorkspace

    $reportRoot = Join-Path $script:TedeDataRoot 'Reports'
    if (-not (Test-Path $reportRoot)) {
        New-Item -Path $reportRoot -ItemType Directory -Force | Out-Null
    }

    $file = Join-Path $reportRoot ('validation_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')

    $lines = @()
    $lines += 'TedeTweak Validation Report'
    $lines += 'Date: ' + (Get-Date)
    $lines += ''
    $lines += 'Hardware profile:'
    $lines += Get-TedeHardwareProfile
    $lines += 'GPU Vendor: ' + (Get-GpuVendor)
    $lines += ''

    try {
        $lines += 'Active power scheme:'
        $lines += (powercfg /getactivescheme | Out-String).Trim()
    }
    catch {
        $lines += 'SKIP power scheme'
    }

    $lines += ''

    try {
        $lines += 'BCD excerpt:'
        $lines += (bcdedit /enum | Out-String).Trim()
    }
    catch {
        $lines += 'SKIP bcdedit'
    }

    $lines += ''

    try {
        $lines += 'Adapters up:'
        $lines += (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Format-Table Name, InterfaceDescription, Status -AutoSize | Out-String).Trim()
    }
    catch {
        $lines += 'SKIP netadapter'
    }

    Set-Content -Path $file -Value $lines -Encoding UTF8
    return 'Validation report salvato: ' + $file
}

function Apply-FortniteSpecific {
    $applied = @()
    $roots = @(
        'C:\Program Files\Epic Games',
        'C:\Program Files (x86)\Epic Games',
        'D:\Epic Games',
        'E:\Epic Games'
    )

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

# =========================================================
# GUI
# =========================================================

Ensure-RunAsAdmin
Initialize-TedeWorkspace

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TedeTweak Gear Panel"
        Height="840"
        Width="1140"
        WindowStartupLocation="CenterScreen"
        Background="#08131E"
        Foreground="#F8E7B6">
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="220"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <Border Grid.Column="0" Background="#14100C" BorderBrush="#8A6735" BorderThickness="0,0,1,0">
            <StackPanel Margin="14">
                <TextBlock Text="☠ TedeTweak"
                           FontSize="24"
                           FontWeight="Bold"
                           Foreground="#F4D28C"
                           Margin="0,0,0,4"/>
                <TextBlock Text="Gear Panel"
                           FontSize="21"
                           FontWeight="Bold"
                           Foreground="#FFF1CC"
                           Margin="0,0,0,18"/>

                <Button Name="BtnNavPreset" Content="Crew Routes" Height="44" Margin="0,0,0,10" Background="#3A2416" Foreground="#F7E7C1" BorderBrush="#8A6735"/>
                <Button Name="BtnNavTweaks" Content="Ship Systems" Height="44" Margin="0,0,0,10" Background="#20150E" Foreground="#F7E7C1" BorderBrush="#8A6735"/>
                <Button Name="BtnNavInfo" Content="Captain Log" Height="44" Margin="0,0,0,10" Background="#20150E" Foreground="#F7E7C1" BorderBrush="#8A6735"/>
            </StackPanel>
        </Border>

        <Grid Grid.Column="1" Margin="14">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <Grid Grid.Row="0" Margin="0,0,0,10">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0">
                    <TextBlock Text="TedeTweak Gear Panel" FontSize="28" FontWeight="Bold" Foreground="#FFF1CC"/>
                    <TextBlock Name="TxtModeLabel" Text="Route: GEAR 2" FontSize="13" Margin="0,4,0,0" Foreground="#D9C7A0"/>
                </StackPanel>

                <Border Name="ModeChipBorder" Grid.Column="1" Background="#8C4C22" BorderBrush="#D6A84F" BorderThickness="1" CornerRadius="14" Padding="14,7" VerticalAlignment="Center">
                    <TextBlock Name="TxtModeChip" Text="GEAR 2" FontWeight="SemiBold" Foreground="#FFF4DA"/>
                </Border>
            </Grid>

            <TabControl Name="MainTab" Grid.Row="1" Background="#14100C" BorderBrush="#8A6735">

                <TabItem Header="Crew Routes">
                    <Grid Background="#14100C" Margin="8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="330"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <StackPanel Grid.Column="0" Margin="0,0,12,0">

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Crew Route" FontSize="15" FontWeight="Bold" Foreground="#F4D28C" Margin="0,0,0,8"/>
                                    <RadioButton Name="RbGear2" Content="Gear 2 (Recommended / Safe Comp)" IsChecked="True" Margin="0,0,0,6" Foreground="#F7E7C1"/>
                                    <RadioButton Name="RbGear4" Content="Gear 4 (Hard Comp)" Margin="0,0,0,6" Foreground="#F7E7C1"/>
                                    <RadioButton Name="RbGear5" Content="Gear 5 (Max Mode)" Margin="0,0,0,6" Foreground="#F7E7C1"/>
                                    <RadioButton Name="RbGearCustom" Content="Gear Custom (Manuale)" Margin="0,0,0,0" Foreground="#F7E7C1"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Configurazione hardware" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,8"/>
                                    <TextBlock Text="Rete" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <ComboBox Name="CmbNetMode" SelectedIndex="0" Margin="0,0,0,10">
                                        <ComboBoxItem Content="LAN / Ethernet"/>
                                        <ComboBoxItem Content="Wi-Fi"/>
                                    </ComboBox>
                                    <TextBlock Text="CPU" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <ComboBox Name="CmbCpu" SelectedIndex="0" Margin="0,0,0,10">
                                        <ComboBoxItem Content="AMD Ryzen"/>
                                        <ComboBoxItem Content="Intel Core"/>
                                    </ComboBox>
                                    <TextBlock Text="GPU" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <ComboBox Name="CmbGpu" SelectedIndex="1">
                                        <ComboBoxItem Content="AMD Radeon"/>
                                        <ComboBoxItem Content="NVIDIA GeForce"/>
                                        <ComboBoxItem Content="Intel Arc"/>
                                    </ComboBox>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12">
                                <StackPanel>
                                    <TextBlock Text="Quick tools" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,8"/>
                                    <Button Name="BtnCreateBackup" Content="Create safety backup" Height="34" Margin="0,0,0,8" Background="#4A2E1B" Foreground="#FFF1CC" BorderBrush="#9A7A49"/>
                                    <Button Name="BtnOpenData" Content="Open TedeTweakData" Height="34" Background="#4A2E1B" Foreground="#FFF1CC" BorderBrush="#9A7A49"/>
                                </StackPanel>
                            </Border>
                        </StackPanel>

                        <Border Grid.Column="1" Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="14">
                            <StackPanel>
                                <TextBlock Text="Crew Route Description" FontSize="16" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,8"/>
                                <TextBlock Name="TxtPresetDescription"
                                           Text="Gear 2: preset safe competitivo con servizi base, debloat safe, power advanced, scheduler, input, USB, memory lite, cleanup safe, gaming common e chiusura leggera dei processi inutili."
                                           TextWrapping="Wrap"
                                           Foreground="#F7E7C1"
                                           Margin="0,0,0,12"/>

                                <TextBlock Text="GEAR 2" FontWeight="Bold" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                <TextBlock Text="- base consigliata: safe comp, pulita, stabile e veloce."
                                           TextWrapping="Wrap"
                                           Foreground="#F7E7C1"
                                           Margin="0,0,0,6"/>

                                <TextBlock Text="GEAR 4" FontWeight="Bold" Foreground="#F7E7C1" Margin="0,4,0,4"/>
                                <TextBlock Text="- hard comp: aggiunge rete, cache, NIC tuning, GPU helper, overlay killer e cleanup pro."
                                           TextWrapping="Wrap"
                                           Foreground="#F7E7C1"
                                           Margin="0,0,0,6"/>

                                <TextBlock Text="GEAR 5" FontWeight="Bold" Foreground="#F7E7C1" Margin="0,4,0,4"/>
                                <TextBlock Text="- max mode: aggiunge memory aggressive, MSI, BCD, security optional, vendor cleanup e Fortnite."
                                           TextWrapping="Wrap"
                                           Foreground="#F7E7C1"
                                           Margin="0,0,0,6"/>

                                <TextBlock Text="GEAR CUSTOM" FontWeight="Bold" Foreground="#F7E7C1" Margin="0,4,0,4"/>
                                <TextBlock Text="- usa solo le checkbox selezionate nel tab Tweaks."
                                           TextWrapping="Wrap"
                                           Foreground="#F7E7C1"
                                           Margin="0,0,0,12"/>

                                <Separator Margin="0,8,0,10" Background="#8A6735"/>

                                <TextBlock Text="Hardware attuale" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,6"/>
                                <TextBlock Name="TxtHardwareInfo" TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,10"/>

                                <TextBlock Text="Livello rischio attuale" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,6"/>
                                <TextBlock Name="TxtRiskLevel" Text="BASSO" Foreground="#9FE870" Margin="0,0,0,10"/>

                                <TextBlock Text="Warning" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,6"/>
                                <TextBlock Name="TxtWarnings" TextWrapping="Wrap" Foreground="#F7E7C1"/>
                            </StackPanel>
                        </Border>
                    </Grid>
                </TabItem>

                <TabItem Header="Ship Systems">
                    <ScrollViewer Background="#14100C">
                        <StackPanel Margin="8">

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Ship Services and Cargo Cleanup" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,4"/>
                                    <TextBlock Text="Servizi Windows e rimozione bloatware selettiva." Foreground="#F7E7C1" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkServicesBase" Content="Services base (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkDebloatSafe" Content="Debloat safe (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkDebloatAggressive" Content="Debloat aggressive (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkDebloatExtreme" Content="Debloat extreme custom (reale)" Foreground="#F7E7C1"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Debloat extreme custom" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,4"/>
                                    <TextBlock Text="Seleziona manualmente i pacchetti da rimuovere. Le opzioni sotto vengono usate solo se il toggle Debloat extreme custom è attivo." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,8"/>

                                    <WrapPanel Margin="0,0,0,10">
                                        <Button Name="BtnDebloatRecommended" Content="Select recommended" Width="140" Height="30" Margin="0,0,8,0" Background="#4A2E1B" Foreground="#FFF1CC" BorderBrush="#9A7A49"/>
                                        <Button Name="BtnDebloatAll" Content="Select all" Width="110" Height="30" Margin="0,0,8,0" Background="#4A2E1B" Foreground="#FFF1CC" BorderBrush="#9A7A49"/>
                                        <Button Name="BtnDebloatClear" Content="Clear all" Width="110" Height="30" Background="#4A2E1B" Foreground="#FFF1CC" BorderBrush="#9A7A49"/>
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
                                    <TextBlock Text="Engine Core" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,4"/>
                                    <TextBlock Text="Blocchi per input delay, reattività e frametime più stabili." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkPowerAdvanced" Content="Power advanced (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkScheduler" Content="Scheduler / MMCSS (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkInput" Content="Input tweaks (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkUsb" Content="USB low latency (reale)" Foreground="#F7E7C1"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Memory" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,4"/>
                                    <TextBlock Text="Tweak memoria lite o aggressivi." Foreground="#F7E7C1" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkMemoryLite" Content="Memory lite (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkMemoryAggressive" Content="Memory aggressive (reale)" Foreground="#F7E7C1"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Background cleanup" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,4"/>
                                    <TextBlock Text="Riduce esperienze Windows e processi non essenziali senza toccare app utente comuni." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkCleanupSafe" Content="Background cleanup safe (reale)" Foreground="#F7E7C1"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="System finish" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,4"/>
                                    <TextBlock Text="Storage, overlay display, pulizia cache e cleanup processi Windows non essenziali." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkStorage" Content="Storage advanced (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkDisplay" Content="Display pipeline (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkCache" Content="Cache cleanup (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkCleanupPro" Content="Process cleanup safe pro (reale)" Foreground="#F7E7C1"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Network and timer" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,4"/>
                                    <TextBlock Text="Tuning rete competitiva, MSI mode e timer di boot." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkNetworkCommon" Content="Network common (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkNetworkAdapter" Content="Network adapter mode (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkMSI" Content="MSI mode (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkBCD" Content="BCD / timer tweaks (reale)" Foreground="#F7E7C1"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Cannons and GPU" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,4"/>
                                    <TextBlock Text="Vendor-specific helper tuning e tweak generici per game exe." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkGpuVendor" Content="GPU vendor-specific helper (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkGameExeGeneric" Content="Game EXE generic flags (reale)" Foreground="#F7E7C1" Margin="0,0,0,6"/>
                                    <TextBlock Text="Percorso game exe" Foreground="#D9C7A0" Margin="0,4,0,4"/>
                                    <TextBox Name="TxtGameExePath" Text="" Background="#3A2416" Foreground="#FFF1CC" BorderBrush="#334155" Padding="8"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#2A1A12" BorderBrush="#8A6735" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Captain Optional" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,4"/>
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
                                    <TextBlock Text="Battle Mode" FontSize="15" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,4"/>
                                    <TextBlock Text="GameDVR, Game Mode, HAGS e Fortnite." Foreground="#F7E7C1" Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkGaming" Content="Gaming common (reale)" Foreground="#F7E7C1" Margin="0,0,0,4"/>
                                    <CheckBox Name="ChkFortnite" Content="Fortnite specific (reale)" Foreground="#F7E7C1"/>
                                </StackPanel>
                            </Border>

                        </StackPanel>
                    </ScrollViewer>
                </TabItem>

                <TabItem Header="Captain Log">
                    <Grid Background="#14100C">
                        <StackPanel Margin="24">
                            <TextBlock Text="TedeTweak Gear Panel" FontSize="18" FontWeight="Bold" Foreground="#FFF1CC" Margin="0,0,0,8"/>
                            <TextBlock Text="Rewrite pulito con preset Gear, backup, report, debloat custom e moduli tweak separati." TextWrapping="Wrap" Foreground="#F7E7C1" Margin="0,0,0,12"/>
                            <TextBox Name="TxtOutput" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" Background="#120C08" Foreground="#F7E7C1" BorderBrush="#8A6735" MinHeight="420"/>
                        </StackPanel>
                    </Grid>
                </TabItem>

            </TabControl>

            <Grid Grid.Row="2" Margin="0,10,0,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <TextBlock Name="TxtStatus" Grid.Column="0" Text="Pronto." VerticalAlignment="Center" Foreground="#9CA3AF"/>

                <WrapPanel Grid.Column="1">
                    <Button Name="BtnPreview" Content="Preview summary" Width="130" Height="36" Margin="0,0,8,0" Background="#4A2E1B" Foreground="#FFF4DA" BorderBrush="#D6A84F"/>
                    <Button Name="BtnApply" Content="Set Sail / Apply Tweaks" Width="170" Height="36" Background="#B63A2B" Foreground="#FFF4DA" BorderBrush="#D6A84F"/>
                </WrapPanel>
            </Grid>

        </Grid>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# =========================================================
# FIND CONTROLS
# =========================================================

$MainTab = $window.FindName('MainTab')
$BtnNavPreset = $window.FindName('BtnNavPreset')
$BtnNavTweaks = $window.FindName('BtnNavTweaks')
$BtnNavInfo = $window.FindName('BtnNavInfo')

$RbGear2 = $window.FindName('RbGear2')
$RbGear4 = $window.FindName('RbGear4')
$RbGear5 = $window.FindName('RbGear5')
$RbGearCustom = $window.FindName('RbGearCustom')

$TxtModeLabel = $window.FindName('TxtModeLabel')
$TxtModeChip = $window.FindName('TxtModeChip')
$ModeChipBorder = $window.FindName('ModeChipBorder')
$TxtPresetDescription = $window.FindName('TxtPresetDescription')
$TxtStatus = $window.FindName('TxtStatus')
$TxtOutput = $window.FindName('TxtOutput')
$TxtHardwareInfo = $window.FindName('TxtHardwareInfo')
$TxtRiskLevel = $window.FindName('TxtRiskLevel')
$TxtWarnings = $window.FindName('TxtWarnings')

$BtnApply = $window.FindName('BtnApply')
$BtnPreview = $window.FindName('BtnPreview')
$BtnCreateBackup = $window.FindName('BtnCreateBackup')
$BtnOpenData = $window.FindName('BtnOpenData')

$CmbNetMode = $window.FindName('CmbNetMode')
$TxtGameExePath = $window.FindName('TxtGameExePath')

$ChkServicesBase = $window.FindName('ChkServicesBase')
$ChkDebloatSafe = $window.FindName('ChkDebloatSafe')
$ChkDebloatAggressive = $window.FindName('ChkDebloatAggressive')
$ChkDebloatExtreme = $window.FindName('ChkDebloatExtreme')

$ChkDebloatUsers = $window.FindName('ChkDebloatUsers')
$ChkDebloatProvisioned = $window.FindName('ChkDebloatProvisioned')

$BtnDebloatRecommended = $window.FindName('BtnDebloatRecommended')
$BtnDebloatAll = $window.FindName('BtnDebloatAll')
$BtnDebloatClear = $window.FindName('BtnDebloatClear')

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

$ChkNicAdvanced = $window.FindName('ChkNicAdvanced')
$ChkOverlayKiller = $window.FindName('ChkOverlayKiller')
$ChkSecurityOptional = $window.FindName('ChkSecurityOptional')
$ChkVendorCleanup = $window.FindName('ChkVendorCleanup')
$ChkValidationReport = $window.FindName('ChkValidationReport')

$ChkGaming = $window.FindName('ChkGaming')
$ChkFortnite = $window.FindName('ChkFortnite')

$DebloatBoxes = [ordered]@{
    'Clipchamp' = $window.FindName('DbClipchamp')
    'Bing News' = $window.FindName('DbBingNews')
    'Get Help' = $window.FindName('DbGetHelp')
    'Get Started' = $window.FindName('DbGetStarted')
    'Office Hub' = $window.FindName('DbOfficeHub')
    'Solitaire' = $window.FindName('DbSolitaire')
    'People' = $window.FindName('DbPeople')
    'Skype' = $window.FindName('DbSkype')
    'Teams Consumer' = $window.FindName('DbTeams')
    'Xbox TCUI' = $window.FindName('DbXboxTCUI')
    'Xbox App' = $window.FindName('DbXboxApp')
    'Xbox Game Overlay' = $window.FindName('DbXboxGameOverlay')
    'Xbox Gaming Overlay' = $window.FindName('DbXboxGamingOverlay')
    'Xbox Identity Provider' = $window.FindName('DbXboxIdentity')
    'Xbox Speech To Text' = $window.FindName('DbXboxSpeech')
    'Phone Link' = $window.FindName('DbPhoneLink')
    'Groove Music' = $window.FindName('DbGroove')
    'Movies and TV' = $window.FindName('DbMovies')
    'To Do' = $window.FindName('DbTodo')
    'Family' = $window.FindName('DbFamily')
    'Quick Assist' = $window.FindName('DbQuickAssist')
    'Dev Home' = $window.FindName('DbDevHome')
    'Feedback Hub' = $window.FindName('DbFeedbackHub')
    'Maps' = $window.FindName('DbMaps')
    'Camera' = $window.FindName('DbCamera')
    'Sound Recorder' = $window.FindName('DbSoundRecorder')
    'Alarms' = $window.FindName('DbAlarms')
    'Mail and Calendar' = $window.FindName('DbMailCalendar')
}

$RecommendedDebloat = @(
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

# =========================================================
# UI HELPERS
# =========================================================

function Set-DebloatSelection {
    param([string[]]$Items)

    foreach ($key in $DebloatBoxes.Keys) {
        $DebloatBoxes[$key].IsChecked = $false
    }

    foreach ($item in $Items) {
        if ($DebloatBoxes.Contains($item)) {
            $DebloatBoxes[$item].IsChecked = $true
        }
    }
}

function Get-SelectedDebloatItems {
    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($key in $DebloatBoxes.Keys) {
        if ($DebloatBoxes[$key].IsChecked) {
            $selected.Add($key)
        }
    }
    return $selected
}

function Get-NetModeText {
    if ($CmbNetMode.SelectedIndex -eq 1) { return 'Wi-Fi' }
    return 'LAN'
}

function Update-HardwareInfoBlock {
    $lines = @()
    $lines += Get-TedeHardwareProfile
    $lines += 'NET MODE: ' + (Get-NetModeText)
    $TxtHardwareInfo.Text = ($lines -join [Environment]::NewLine)
}

function Update-RiskInfo {
    $warnings = New-Object System.Collections.Generic.List[string]

    if ($ChkDebloatAggressive.IsChecked) { $warnings.Add('Debloat aggressive può rimuovere app secondarie Microsoft.') }
    if ($ChkDebloatExtreme.IsChecked) { $warnings.Add('Debloat extreme usa la tua selezione manuale ed è più facile fare danni.') }
    if ($ChkMSI.IsChecked) { $warnings.Add('MSI mode è più aggressivo e dipende dall’hardware.') }
    if ($ChkBCD.IsChecked) { $warnings.Add('BCD / timer tweaks modificano il boot configuration data.') }
    if ($ChkSecurityOptional.IsChecked) { $warnings.Add('Security optional spegne VBS/HVCI e riduce protezioni.') }

    $risk = Get-TedeRiskLevel `
        -HasAggressive ([bool]$ChkDebloatAggressive.IsChecked) `
        -HasBCD ([bool]$ChkBCD.IsChecked) `
        -HasMSI ([bool]$ChkMSI.IsChecked) `
        -HasSecurity ([bool]$ChkSecurityOptional.IsChecked) `
        -HasExtremeDebloat ([bool]$ChkDebloatExtreme.IsChecked)

    $TxtRiskLevel.Text = $risk

    switch ($risk) {
        'BASSO' { $TxtRiskLevel.Foreground = '#9FE870' }
        'MEDIO' { $TxtRiskLevel.Foreground = '#F7D774' }
        'ALTO'  { $TxtRiskLevel.Foreground = '#FF8B7A' }
    }

    if ($warnings.Count -eq 0) {
        $TxtWarnings.Text = 'Nessun warning importante con la selezione attuale.'
    }
    else {
        $TxtWarnings.Text = ($warnings -join [Environment]::NewLine)
    }
}

function Set-ModeDisplay {
    if ($RbGear2.IsChecked) {
        $TxtModeLabel.Text = 'Route: GEAR 2'
        $TxtModeChip.Text = 'GEAR 2'
        $ModeChipBorder.Background = '#8C4C22'
        $ModeChipBorder.BorderBrush = '#D6A84F'
        $TxtModeChip.Foreground = '#FFF4DA'
        $TxtPresetDescription.Text = 'Gear 2: preset safe competitivo con servizi base, debloat safe, power advanced, scheduler, input, USB, memory lite, cleanup safe, gaming common e chiusura leggera dei processi inutili.'
    }
    elseif ($RbGear4.IsChecked) {
        $TxtModeLabel.Text = 'Route: GEAR 4'
        $TxtModeChip.Text = 'GEAR 4'
        $ModeChipBorder.Background = '#A63B2F'
        $ModeChipBorder.BorderBrush = '#E1B866'
        $TxtModeChip.Foreground = '#FFF4DA'
        $TxtPresetDescription.Text = 'Gear 4: hard comp con base completa più storage, display, cache, cleanup pro, rete, NIC tuning, GPU helper, overlay killer e validation report.'
    }
    elseif ($RbGear5.IsChecked) {
        $TxtModeLabel.Text = 'Route: GEAR 5'
        $TxtModeChip.Text = 'GEAR 5'
        $ModeChipBorder.Background = '#D9F3FF'
        $ModeChipBorder.BorderBrush = '#FFF4DA'
        $TxtModeChip.Foreground = '#12202A'
        $TxtPresetDescription.Text = 'Gear 5: max mode con debloat aggressive, memory aggressive, MSI, BCD, security optional, vendor cleanup, gaming common e Fortnite specific.'
    }
    else {
        $TxtModeLabel.Text = 'Route: GEAR CUSTOM'
        $TxtModeChip.Text = 'GEAR CUSTOM'
        $ModeChipBorder.Background = '#5C2E91'
        $ModeChipBorder.BorderBrush = '#D6A84F'
        $TxtModeChip.Foreground = '#FFF4DA'
        $TxtPresetDescription.Text = 'Gear Custom: modalità manuale con controllo totale delle checkbox e dei blocchi del pannello.'
    }

    Update-HardwareInfoBlock
    Update-RiskInfo
}

function Clear-AllMainTweaks {
    $ChkServicesBase.IsChecked = $false
    $ChkDebloatSafe.IsChecked = $false
    $ChkDebloatAggressive.IsChecked = $false
    $ChkDebloatExtreme.IsChecked = $false

    $ChkPowerAdvanced.IsChecked = $false
    $ChkScheduler.IsChecked = $false
    $ChkInput.IsChecked = $false
    $ChkUsb.IsChecked = $false

    $ChkMemoryLite.IsChecked = $false
    $ChkMemoryAggressive.IsChecked = $false

    $ChkCleanupSafe.IsChecked = $false

    $ChkStorage.IsChecked = $false
    $ChkDisplay.IsChecked = $false
    $ChkCache.IsChecked = $false
    $ChkCleanupPro.IsChecked = $false

    $ChkNetworkCommon.IsChecked = $false
    $ChkNetworkAdapter.IsChecked = $false
    $ChkMSI.IsChecked = $false
    $ChkBCD.IsChecked = $false

    $ChkGpuVendor.IsChecked = $false
    $ChkGameExeGeneric.IsChecked = $false

    $ChkNicAdvanced.IsChecked = $false
    $ChkOverlayKiller.IsChecked = $false
    $ChkSecurityOptional.IsChecked = $false
    $ChkVendorCleanup.IsChecked = $false
    $ChkValidationReport.IsChecked = $false

    $ChkGaming.IsChecked = $false
    $ChkFortnite.IsChecked = $false
}

function Set-Gear2Preset {
    Clear-AllMainTweaks

    $ChkServicesBase.IsChecked = $true
    $ChkDebloatSafe.IsChecked = $true

    $ChkPowerAdvanced.IsChecked = $true
    $ChkScheduler.IsChecked = $true
    $ChkInput.IsChecked = $true
    $ChkUsb.IsChecked = $true

    $ChkMemoryLite.IsChecked = $true
    $ChkCleanupSafe.IsChecked = $true

    $ChkGaming.IsChecked = $true
    $ChkValidationReport.IsChecked = $true

    Set-DebloatSelection -Items $RecommendedDebloat
    $TxtStatus.Text = 'Preset GEAR 2 caricato.'
    Update-RiskInfo
}

function Set-Gear4Preset {
    Clear-AllMainTweaks

    $ChkServicesBase.IsChecked = $true
    $ChkDebloatSafe.IsChecked = $true

    $ChkPowerAdvanced.IsChecked = $true
    $ChkScheduler.IsChecked = $true
    $ChkInput.IsChecked = $true
    $ChkUsb.IsChecked = $true

    $ChkMemoryLite.IsChecked = $true
    $ChkCleanupSafe.IsChecked = $true

    $ChkStorage.IsChecked = $true
    $ChkDisplay.IsChecked = $true
    $ChkCache.IsChecked = $true
    $ChkCleanupPro.IsChecked = $true

    $ChkNetworkCommon.IsChecked = $true
    $ChkNetworkAdapter.IsChecked = $true

    $ChkGpuVendor.IsChecked = $true
    $ChkNicAdvanced.IsChecked = $true
    $ChkOverlayKiller.IsChecked = $true
    $ChkValidationReport.IsChecked = $true

    $ChkGaming.IsChecked = $true

    Set-DebloatSelection -Items $RecommendedDebloat
    $TxtStatus.Text = 'Preset GEAR 4 caricato.'
    Update-RiskInfo
}

function Set-Gear5Preset {
    Clear-AllMainTweaks

    $ChkServicesBase.IsChecked = $true
    $ChkDebloatAggressive.IsChecked = $true

    $ChkPowerAdvanced.IsChecked = $true
    $ChkScheduler.IsChecked = $true
    $ChkInput.IsChecked = $true
    $ChkUsb.IsChecked = $true

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
    $ChkNicAdvanced.IsChecked = $true
    $ChkOverlayKiller.IsChecked = $true
    $ChkSecurityOptional.IsChecked = $true
    $ChkVendorCleanup.IsChecked = $true
    $ChkValidationReport.IsChecked = $true

    $ChkGaming.IsChecked = $true
    $ChkFortnite.IsChecked = $true

    Set-DebloatSelection -Items @($DebloatBoxes.Keys)
    $TxtStatus.Text = 'Preset GEAR 5 caricato.'
    Update-RiskInfo
}

function Set-GearCustomPreset {
    Clear-AllMainTweaks
    Set-DebloatSelection -Items @()
    $TxtStatus.Text = 'Modalità GEAR CUSTOM attiva. Modifica le checkbox a piacere.'
    Update-RiskInfo
}

function Get-SelectedTweaks {
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

    return $selected
}

function Build-PreviewSummary {
    $lines = @()
    $lines += 'Preset attivo: ' + $TxtModeChip.Text
    $lines += 'Rete: ' + (Get-NetModeText)
    $lines += ''
    $lines += 'Tweaks selezionati:'

    $selected = Get-SelectedTweaks
    if ($selected.Count -eq 0) {
        $lines += '- Nessuno'
    }
    else {
        foreach ($item in $selected) {
            $lines += '- ' + $item
        }
    }

    if ($ChkDebloatExtreme.IsChecked) {
        $lines += ''
        $lines += 'Debloat extreme scelti:'
        $db = Get-SelectedDebloatItems
        if ($db.Count -eq 0) {
            $lines += '- Nessuna app selezionata'
        }
        else {
            foreach ($item in $db) { $lines += '- ' + $item }
        }
    }

    return ($lines -join [Environment]::NewLine)
}

# =========================================================
# EVENTS
# =========================================================

$BtnNavPreset.Add_Click({ $MainTab.SelectedIndex = 0 })
$BtnNavTweaks.Add_Click({ $MainTab.SelectedIndex = 1 })
$BtnNavInfo.Add_Click({ $MainTab.SelectedIndex = 2 })

$RbGear2.Add_Checked({ Set-ModeDisplay; Set-Gear2Preset })
$RbGear4.Add_Checked({ Set-ModeDisplay; Set-Gear4Preset })
$RbGear5.Add_Checked({ Set-ModeDisplay; Set-Gear5Preset })
$RbGearCustom.Add_Checked({ Set-ModeDisplay; Set-GearCustomPreset })

$ChkMemoryLite.Add_Checked({
    if ($ChkMemoryAggressive.IsChecked) { $ChkMemoryAggressive.IsChecked = $false }
    Update-RiskInfo
})
$ChkMemoryAggressive.Add_Checked({
    if ($ChkMemoryLite.IsChecked) { $ChkMemoryLite.IsChecked = $false }
    Update-RiskInfo
})

$ChkDebloatSafe.Add_Checked({
    if ($ChkDebloatAggressive.IsChecked) { $ChkDebloatAggressive.IsChecked = $false }
    if ($ChkDebloatExtreme.IsChecked) { $ChkDebloatExtreme.IsChecked = $false }
    Update-RiskInfo
})
$ChkDebloatAggressive.Add_Checked({
    if ($ChkDebloatSafe.IsChecked) { $ChkDebloatSafe.IsChecked = $false }
    if ($ChkDebloatExtreme.IsChecked) { $ChkDebloatExtreme.IsChecked = $false }
    Update-RiskInfo
})
$ChkDebloatExtreme.Add_Checked({
    if ($ChkDebloatSafe.IsChecked) { $ChkDebloatSafe.IsChecked = $false }
    if ($ChkDebloatAggressive.IsChecked) { $ChkDebloatAggressive.IsChecked = $false }
    Update-RiskInfo
})

foreach ($cb in @(
    $ChkServicesBase,$ChkPowerAdvanced,$ChkScheduler,$ChkInput,$ChkUsb,$ChkCleanupSafe,
    $ChkStorage,$ChkDisplay,$ChkCache,$ChkCleanupPro,$ChkNetworkCommon,$ChkNetworkAdapter,
    $ChkMSI,$ChkBCD,$ChkGpuVendor,$ChkGameExeGeneric,$ChkNicAdvanced,$ChkOverlayKiller,
    $ChkSecurityOptional,$ChkVendorCleanup,$ChkValidationReport,$ChkGaming,$ChkFortnite
)) {
    $cb.Add_Checked({ Update-RiskInfo })
    $cb.Add_Unchecked({ Update-RiskInfo })
}

$BtnDebloatRecommended.Add_Click({
    Set-DebloatSelection -Items $RecommendedDebloat
    $TxtStatus.Text = 'Debloat recommended selezionato.'
})

$BtnDebloatAll.Add_Click({
    Set-DebloatSelection -Items @($DebloatBoxes.Keys)
    $TxtStatus.Text = 'Tutti i debloat selezionati.'
})

$BtnDebloatClear.Add_Click({
    Set-DebloatSelection -Items @()
    $TxtStatus.Text = 'Debloat custom pulito.'
})

$BtnCreateBackup.Add_Click({
    $items = New-TedeSafetyBackup
    foreach ($entry in $items) { Write-TedeLog $entry 'BACKUP' }
    $TxtOutput.Text = ($items -join [Environment]::NewLine)
    $TxtStatus.Text = 'Backup creato.'
    $MainTab.SelectedIndex = 2
})

$BtnOpenData.Add_Click({
    Open-TedePath -Path $script:TedeDataRoot
})

$BtnPreview.Add_Click({
    $TxtOutput.Text = Build-PreviewSummary
    $TxtStatus.Text = 'Preview generata.'
    $MainTab.SelectedIndex = 2
})

$BtnApply.Add_Click({
    $done = New-Object System.Collections.Generic.List[string]
    $selected = Get-SelectedTweaks

    if ($selected.Count -eq 0) {
        $TxtStatus.Text = 'Nessun tweak selezionato.'
        [System.Windows.MessageBox]::Show('Non hai selezionato nessun tweak.', 'TedeTweak') | Out-Null
        return
    }

    $warnings = @()
    if ($ChkDebloatAggressive.IsChecked) { $warnings += 'Debloat aggressive' }
    if ($ChkDebloatExtreme.IsChecked) { $warnings += 'Debloat extreme custom' }
    if ($ChkMSI.IsChecked) { $warnings += 'MSI mode' }
    if ($ChkBCD.IsChecked) { $warnings += 'BCD / timer tweaks' }
    if ($ChkSecurityOptional.IsChecked) { $warnings += 'Security optional profile' }

    $riskNow = Get-TedeRiskLevel `
        -HasAggressive ([bool]$ChkDebloatAggressive.IsChecked) `
        -HasBCD ([bool]$ChkBCD.IsChecked) `
        -HasMSI ([bool]$ChkMSI.IsChecked) `
        -HasSecurity ([bool]$ChkSecurityOptional.IsChecked) `
        -HasExtremeDebloat ([bool]$ChkDebloatExtreme.IsChecked)

    if (-not (Confirm-TedeSensitiveSelection -RiskText $riskNow -Warnings $warnings)) {
        $TxtStatus.Text = "Applicazione annullata dall'utente."
        return
    }

    try {
        $backupItems = New-TedeSafetyBackup
        foreach ($entry in $backupItems) {
            $done.Add($entry)
            Write-TedeLog $entry 'BACKUP'
        }

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
                foreach ($item in (Apply-DebloatSelection -Items $customItems -RemoveForUsers ([bool]$ChkDebloatUsers.IsChecked) -RemoveProvisioned ([bool]$ChkDebloatProvisioned.IsChecked))) {
                    $done.Add($item)
                }
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
            $mode = Get-NetModeText
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
            $mode = Get-NetModeText
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

        foreach ($entry in $done) {
            Write-TedeLog $entry 'APPLY'
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

        $TxtOutput.Text = ($summary -join [Environment]::NewLine)
        $TxtStatus.Text = 'Tweaks applicati: ' + $done.Count
        $MainTab.SelectedIndex = 2
        [System.Windows.MessageBox]::Show('Tweaks applicati. Controlla il Captain Log per il riepilogo completo.', 'TedeTweak') | Out-Null
    }
    catch {
        $TxtStatus.Text = 'Errore: ' + $_.Exception.Message
        $TxtOutput.Text = $_.Exception.Message
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'TedeTweak - Errore') | Out-Null
    }
})

$CmbNetMode.Add_SelectionChanged({
    Update-HardwareInfoBlock
})

# =========================================================
# INIT
# =========================================================

Update-HardwareInfoBlock
Update-RiskInfo
Set-ModeDisplay
Set-Gear2Preset
$MainTab.SelectedIndex = 0

$null = $window.ShowDialog()
