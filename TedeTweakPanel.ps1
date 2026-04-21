# ==========================
# TedeTweakPanel.ps1 - v0.2
# GUI con Preset + Tweaks
# ==========================

Add-Type -AssemblyName PresentationFramework

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TedeTweak Panel"
        Height="560"
        Width="960"
        WindowStartupLocation="CenterScreen"
        Background="#101218"
        Foreground="#F3F4F6">

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="180"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- SIDEBAR -->
        <Border Grid.Column="0" Background="#151924">
            <StackPanel Margin="12">
                <TextBlock Text="TedeTweak"
                           FontSize="20"
                           FontWeight="Bold"
                           Margin="0,0,0,16"/>

                <Button Name="BtnNavPreset"
                        Content="Preset"
                        Height="34"
                        Margin="0,0,0,8"
                        Background="#1E2430"
                        Foreground="White"
                        BorderBrush="#31394A"/>

                <Button Name="BtnNavTweaks"
                        Content="Tweaks"
                        Height="34"
                        Margin="0,0,0,8"
                        Background="#11151E"
                        Foreground="White"
                        BorderBrush="#31394A"/>

                <Button Name="BtnNavInfo"
                        Content="Info"
                        Height="34"
                        Margin="0,0,0,8"
                        Background="#11151E"
                        Foreground="White"
                        BorderBrush="#31394A"/>
            </StackPanel>
        </Border>

        <!-- MAIN AREA -->
        <Grid Grid.Column="1" Margin="14">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- HEADER -->
            <Grid Grid.Row="0" Margin="0,0,0,10">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0">
                    <TextBlock Text="TedeTweak Panel"
                               FontSize="24"
                               FontWeight="Bold"/>
                    <TextBlock Name="TxtModeLabel"
                               Text="Mode: SAFE"
                               FontSize="13"
                               Foreground="#9CA3AF"
                               Margin="0,4,0,0"/>
                </StackPanel>

                <Border Name="ModeChipBorder"
                        Grid.Column="1"
                        Background="#0F766E"
                        CornerRadius="14"
                        Padding="12,6"
                        VerticalAlignment="Center">
                    <TextBlock Name="TxtModeChip"
                               Text="SAFE"
                               FontWeight="SemiBold"
                               Foreground="White"/>
                </Border>
            </Grid>

            <!-- TABCONTROL -->
            <TabControl Name="MainTab"
                        Grid.Row="1"
                        Background="#101218"
                        BorderBrush="#2A3140">

                <!-- TAB PRESET -->
                <TabItem Header="Preset">
                    <Grid Background="#101218" Margin="8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="320"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <!-- Colonna sinistra: preset + HW -->
                        <StackPanel Grid.Column="0" Margin="0,0,12,0">

                            <Border Background="#171C26" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Preset"
                                               FontWeight="Bold"
                                               FontSize="15"
                                               Margin="0,0,0,8"/>

                                    <RadioButton Name="RbSafe"
                                                 Content="SAFE (Consigliato)"
                                                 IsChecked="True"
                                                 Margin="0,0,0,6"/>

                                    <RadioButton Name="RbInsane"
                                                 Content="INSANE (Tryhard)"
                                                 Margin="0,0,0,6"/>

                                    <RadioButton Name="RbCustom"
                                                 Content="CUSTOM (solo checkbox)"
                                                 Margin="0,0,0,2"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#171C26" CornerRadius="8" Padding="12">
                                <StackPanel>
                                    <TextBlock Text="Configurazione hardware"
                                               FontWeight="Bold"
                                               FontSize="15"
                                               Margin="0,0,0,8"/>

                                    <TextBlock Text="Rete" Margin="0,0,0,4"/>
                                    <ComboBox Name="CmbNetMode" SelectedIndex="0" Margin="0,0,0,10">
                                        <ComboBoxItem Content="LAN / Ethernet"/>
                                        <ComboBoxItem Content="Wi-Fi"/>
                                    </ComboBox>

                                    <TextBlock Text="CPU" Margin="0,0,0,4"/>
                                    <ComboBox Name="CmbCpu" SelectedIndex="0" Margin="0,0,0,10">
                                        <ComboBoxItem Content="AMD Ryzen"/>
                                        <ComboBoxItem Content="Intel Core"/>
                                    </ComboBox>

                                    <TextBlock Text="GPU" Margin="0,0,0,4"/>
                                    <ComboBox Name="CmbGpu" SelectedIndex="1">
                                        <ComboBoxItem Content="AMD Radeon"/>
                                        <ComboBoxItem Content="NVIDIA GeForce"/>
                                        <ComboBoxItem Content="Intel Arc"/>
                                    </ComboBox>
                                </StackPanel>
                            </Border>
                        </StackPanel>

                        <!-- Colonna destra: descrizione -->
                        <Border Grid.Column="1" Background="#171C26" CornerRadius="8" Padding="14">
                            <StackPanel>
                                <TextBlock Text="Descrizione preset"
                                           FontWeight="Bold"
                                           FontSize="16"
                                           Margin="0,0,0,8"/>

                                <TextBlock Name="TxtPresetDescription"
                                           Text="SAFE: preset equilibrato per gaming e uso quotidiano."
                                           TextWrapping="Wrap"
                                           Foreground="#D1D5DB"
                                           Margin="0,0,0,12"/>

                                <TextBlock Text="SAFE:"
                                           FontWeight="Bold"
                                           Margin="0,0,0,4"/>
                                <TextBlock Text="• servizi di base, power plan, network, gaming."
                                           Margin="0,0,0,2"/>

                                <TextBlock Text="INSANE:"
                                           FontWeight="Bold"
                                           Margin="8,4,0,4"/>
                                <TextBlock Text="• include servizi aggressivi, memory tweaks, Fortnite specific."
                                           Margin="0,0,0,2"/>

                                <TextBlock Text="CUSTOM:"
                                           FontWeight="Bold"
                                           Margin="8,4,0,4"/>
                                <TextBlock Text="• applica solo i gruppi selezionati nel tab Tweaks."
                                           Margin="0,0,0,2"/>
                            </StackPanel>
                        </Border>
                    </Grid>
                </TabItem>

                <!-- TAB TWEAKS -->
                <TabItem Header="Tweaks">
                    <ScrollViewer Background="#101218">
                        <StackPanel Margin="8">

                            <!-- Performance & Services -->
                            <Border Background="#171C26" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Performance &amp; Services"
                                               FontWeight="Bold"
                                               FontSize="15"
                                               Margin="0,0,0,4"/>
                                    <TextBlock Text="Servizi Windows, scheduler, power plan."
                                               Foreground="#D1D5DB"
                                               Margin="0,0,0,8"/>

                                    <CheckBox Name="ChkServicesBase"
                                              Content="Servizi base (SysMain, Telemetry, ecc.)"
                                              Margin="0,0,0,4"/>

                                    <CheckBox Name="ChkServicesInsane"
                                              Content="Servizi INSANE (disattiva anche update/spooler)"
                                              Margin="0,0,0,4"/>

                                    <CheckBox Name="ChkPower"
                                              Content="Power plan / scheduler ottimizzati"
                                              Margin="0,0,0,2"/>
                                </StackPanel>
                            </Border>

                            <!-- Visual & UX -->
                            <Border Background="#171C26" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Visual &amp; UX"
                                               FontWeight="Bold"
                                               FontSize="15"
                                               Margin="0,0,0,4"/>
                                    <TextBlock Text="Animazioni, trasparenze, privacy shell."
                                               Foreground="#D1D5DB"
                                               Margin="0,0,0,8"/>

                                    <CheckBox Name="ChkVisual"
                                              Content="Visual tweaks (animazioni, effetti)"
                                              Margin="0,0,0,4"/>

                                    <CheckBox Name="ChkPrivacy"
                                              Content="Privacy tweaks (ContentDelivery, ads, ecc.)"
                                              Margin="0,0,0,2"/>
                                </StackPanel>
                            </Border>

                            <!-- Network & Input -->
                            <Border Background="#171C26" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Network &amp; Input"
                                               FontWeight="Bold"
                                               FontSize="15"
                                               Margin="0,0,0,4"/>
                                    <TextBlock Text="TCP/IP, adattatore LAN/Wi-Fi, input, USB."
                                               Foreground="#D1D5DB"
                                               Margin="0,0,0,8"/>

                                    <CheckBox Name="ChkNetCommon"
                                              Content="Network common (TCP parameters)"
                                              Margin="0,0,0,4"/>

                                    <CheckBox Name="ChkNetAdapter"
                                              Content="Network adapter (DNS, power, advanced props)"
                                              Margin="0,0,0,4"/>

                                    <CheckBox Name="ChkInput"
                                              Content="Input (mouse, tastiera, sticky keys)"
                                              Margin="0,0,0,4"/>

                                    <CheckBox Name="ChkUsb"
                                              Content="USB (disable selective suspend)"
                                              Margin="0,0,0,2"/>
                                </StackPanel>
                            </Border>

                            <!-- Fortnite -->
                            <Border Background="#171C26" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Fortnite"
                                               FontWeight="Bold"
                                               FontSize="15"
                                               Margin="0,0,0,4"/>
                                    <TextBlock Text="Ottimizzazioni specifiche solo per Fortnite.exe."
                                               Foreground="#D1D5DB"
                                               Margin="0,0,0,8"/>

                                    <CheckBox Name="ChkFortnite"
                                              Content="Fortnite specific tweaks (AppCompat, FSE, cache)"
                                              Margin="0,0,0,2"/>
                                </StackPanel>
                            </Border>

                        </StackPanel>
                    </ScrollViewer>
                </TabItem>

                <!-- TAB INFO (vuoto per ora) -->
                <TabItem Header="Info">
                    <Grid Background="#101218">
                        <TextBlock Text="TedeTweak v0.2 - GUI test"
                                   HorizontalAlignment="Center"
                                   VerticalAlignment="Center"/>
                    </Grid>
                </TabItem>
            </TabControl>

            <!-- FOOTER -->
            <Grid Grid.Row="2" Margin="0,10,0,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <TextBlock Name="TxtStatus"
                           Grid.Column="0"
                           Text="Pronto."
                           VerticalAlignment="Center"
                           Foreground="#9CA3AF"/>

                <Button Name="BtnApply"
                        Grid.Column="1"
                        Content="Apply Tweaks"
                        Width="150"
                        Height="34"
                        Background="#0F766E"
                        Foreground="White"
                        BorderBrush="#0F766E"/>
            </Grid>
        </Grid>
    </Grid>
</Window>
"@

# --- parsing XAML ---
$reader  = New-Object System.Xml.XmlNodeReader $xaml
$window  = [Windows.Markup.XamlReader]::Load($reader)

# --- referenze controlli ---
$MainTab          = $window.FindName("MainTab")
$BtnNavPreset     = $window.FindName("BtnNavPreset")
$BtnNavTweaks     = $window.FindName("BtnNavTweaks")
$BtnNavInfo       = $window.FindName("BtnNavInfo")

$RbSafe           = $window.FindName("RbSafe")
$RbInsane         = $window.FindName("RbInsane")
$RbCustom         = $window.FindName("RbCustom")

$TxtModeLabel     = $window.FindName("TxtModeLabel")
$TxtModeChip      = $window.FindName("TxtModeChip")
$ModeChipBorder   = $window.FindName("ModeChipBorder")
$TxtPresetDescription = $window.FindName("TxtPresetDescription")
$TxtStatus        = $window.FindName("TxtStatus")
$BtnApply         = $window.FindName("BtnApply")

$ChkServicesBase  = $window.FindName("ChkServicesBase")
$ChkServicesInsane= $window.FindName("ChkServicesInsane")
$ChkPower         = $window.FindName("ChkPower")
$ChkVisual        = $window.FindName("ChkVisual")
$ChkPrivacy       = $window.FindName("ChkPrivacy")
$ChkNetCommon     = $window.FindName("ChkNetCommon")
$ChkNetAdapter    = $window.FindName("ChkNetAdapter")
$ChkInput         = $window.FindName("ChkInput")
$ChkUsb           = $window.FindName("ChkUsb")
$ChkFortnite      = $window.FindName("ChkFortnite")

# --- funzioni helper per la UI ---

function Set-ModeDisplay {
    if ($RbSafe.IsChecked) {
        $TxtModeLabel.Text      = "Mode: SAFE"
        $TxtModeChip.Text       = "SAFE"
        $ModeChipBorder.Background = "#0F766E"
        $TxtPresetDescription.Text = "SAFE: preset equilibrato per gaming e uso quotidiano."
    }
    elseif ($RbInsane.IsChecked) {
        $TxtModeLabel.Text      = "Mode: INSANE"
        $TxtModeChip.Text       = "INSANE"
        $ModeChipBorder.Background = "#B91C1C"
        $TxtPresetDescription.Text = "INSANE: preset aggressivo per prestazioni massime."
    }
    else {
        $TxtModeLabel.Text      = "Mode: CUSTOM"
        $TxtModeChip.Text       = "CUSTOM"
        $ModeChipBorder.Background = "#4B5563"
        $TxtPresetDescription.Text = "CUSTOM: applica solo i gruppi selezionati nel tab Tweaks."
    }
}

function Set-SafePreset {
    $ChkServicesBase.IsChecked   = $true
    $ChkServicesInsane.IsChecked = $false
    $ChkPower.IsChecked          = $true
    $ChkVisual.IsChecked         = $true
    $ChkPrivacy.IsChecked        = $true
    $ChkNetCommon.IsChecked      = $true
    $ChkNetAdapter.IsChecked     = $true
    $ChkInput.IsChecked          = $true
    $ChkUsb.IsChecked            = $true
    $ChkFortnite.IsChecked       = $false
    $TxtStatus.Text              = "Preset SAFE caricato."
}

function Set-InsanePreset {
    $ChkServicesBase.IsChecked   = $true
    $ChkServicesInsane.IsChecked = $true
    $ChkPower.IsChecked          = $true
    $ChkVisual.IsChecked         = $true
    $ChkPrivacy.IsChecked        = $true
    $ChkNetCommon.IsChecked      = $true
    $ChkNetAdapter.IsChecked     = $true
    $ChkInput.IsChecked          = $true
    $ChkUsb.IsChecked            = $true
    $ChkFortnite.IsChecked       = $true
    $TxtStatus.Text              = "Preset INSANE caricato."
}

function Set-CustomPreset {
    $TxtStatus.Text = "Modalità CUSTOM attiva. Modifica le checkbox a piacere."
}

# --- eventi radio preset ---
$RbSafe.Add_Checked({
    Set-ModeDisplay
    Set-SafePreset
})

$RbInsane.Add_Checked({
    Set-ModeDisplay
    Set-InsanePreset
})

$RbCustom.Add_Checked({
    Set-ModeDisplay
    Set-CustomPreset
})

# --- navigazione sidebar -> tab ---
$BtnNavPreset.Add_Click({
    $MainTab.SelectedIndex = 0
})
$BtnNavTweaks.Add_Click({
    $MainTab.SelectedIndex = 1
})
$BtnNavInfo.Add_Click({
    $MainTab.SelectedIndex = 2
})

# --- bottone Apply (per ora solo riepilogo) ---
$BtnApply.Add_Click({
    $selected = @()

    if ($ChkServicesBase.IsChecked)    { $selected += "Servizi base" }
    if ($ChkServicesInsane.IsChecked)  { $selected += "Servizi INSANE" }
    if ($ChkPower.IsChecked)           { $selected += "Power/Scheduler" }
    if ($ChkVisual.IsChecked)          { $selected += "Visual" }
    if ($ChkPrivacy.IsChecked)         { $selected += "Privacy" }
    if ($ChkNetCommon.IsChecked)       { $selected += "Network common" }
    if ($ChkNetAdapter.IsChecked)      { $selected += "Network adapter" }
    if ($ChkInput.IsChecked)           { $selected += "Input" }
    if ($ChkUsb.IsChecked)             { $selected += "USB" }
    if ($ChkFortnite.IsChecked)        { $selected += "Fortnite" }

    if ($selected.Count -eq 0) {
        $TxtStatus.Text = "Nessun tweak selezionato."
        [System.Windows.MessageBox]::Show("Non hai selezionato nessun tweak.", "TedeTweak") | Out-Null
        return
    }

    $TxtStatus.Text = "Selezionati: " + ($selected -join ", ")
    [System.Windows.MessageBox]::Show("Tweaks selezionati:`n`n" + ($selected -join "`n"), "TedeTweak") | Out-Null
})

# stato iniziale
Set-ModeDisplay
Set-SafePreset
$MainTab.SelectedIndex = 0

$null = $window.ShowDialog()
