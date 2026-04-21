# ==========================
# TedeTweakPanel.ps1 - v0.1 clean
# Windows 11 - WPF GUI base
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
        Foreground="#F3F4F6"
        ResizeMode="CanResizeWithGrip">

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="180"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Sidebar -->
        <Border Grid.Column="0" Background="#151924">
            <StackPanel Margin="12">
                <TextBlock Text="TedeTweak"
                           FontSize="20"
                           FontWeight="Bold"
                           Margin="0,0,0,16"/>

                <Button Name="BtnNavHome"
                        Content="Home"
                        Height="36"
                        Margin="0,0,0,8"
                        Background="#1E2430"
                        Foreground="White"
                        BorderBrush="#31394A"/>

                <Button Name="BtnNavPreset"
                        Content="Preset"
                        Height="36"
                        Margin="0,0,0,8"
                        Background="#11151E"
                        Foreground="White"
                        BorderBrush="#31394A"/>

                <Button Name="BtnNavTweaks"
                        Content="Tweaks"
                        Height="36"
                        Margin="0,0,0,8"
                        Background="#11151E"
                        Foreground="White"
                        BorderBrush="#31394A"/>

                <Button Name="BtnNavNetwork"
                        Content="Network"
                        Height="36"
                        Margin="0,0,0,8"
                        Background="#11151E"
                        Foreground="White"
                        BorderBrush="#31394A"/>

                <Button Name="BtnNavInfo"
                        Content="Info"
                        Height="36"
                        Margin="0,0,0,8"
                        Background="#11151E"
                        Foreground="White"
                        BorderBrush="#31394A"/>
            </StackPanel>
        </Border>

        <!-- Main content -->
        <Grid Grid.Column="1" Margin="14">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Header -->
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

            <!-- Tabs -->
            <TabControl Name="MainTab"
                        Grid.Row="1"
                        Background="#101218"
                        BorderBrush="#2A3140">

                <!-- PRESET TAB -->
                <TabItem Header="Preset">
                    <Grid Background="#101218" Margin="8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="320"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

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
                                                 Content="CUSTOM (manuale)"
                                                 Margin="0,0,0,2"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#171C26" CornerRadius="8" Padding="12" Margin="0,0,0,10">
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
                                    <ComboBox Name="CmbGpu" SelectedIndex="1" Margin="0,0,0,0">
                                        <ComboBoxItem Content="AMD Radeon"/>
                                        <ComboBoxItem Content="NVIDIA GeForce"/>
                                        <ComboBoxItem Content="Intel Arc"/>
                                    </ComboBox>
                                </StackPanel>
                            </Border>
                        </StackPanel>

                        <Border Grid.Column="1" Background="#171C26" CornerRadius="8" Padding="14">
                            <StackPanel>
                                <TextBlock Text="Descrizione"
                                           FontWeight="Bold"
                                           FontSize="16"
                                           Margin="0,0,0,8"/>
                                <TextBlock Name="TxtPresetDescription"
                                           Text="SAFE: preset equilibrato per gaming e uso quotidiano."
                                           TextWrapping="Wrap"
                                           Foreground="#D1D5DB"
                                           Margin="0,0,0,12"/>

                                <TextBlock Text="Come funziona"
                                           FontWeight="Bold"
                                           FontSize="14"
                                           Margin="0,0,0,8"/>

                                <TextBlock Text="• SAFE: applica ottimizzazioni più sicure."
                                           Margin="0,0,0,4"/>
                                <TextBlock Text="• INSANE: abilita anche tweak più aggressivi."
                                           Margin="0,0,0,4"/>
                                <TextBlock Text="• CUSTOM: usa solo le checkbox selezionate nel tab Tweaks."
                                           Margin="0,0,0,4"/>
                            </StackPanel>
                        </Border>
                    </Grid>
                </TabItem>

                <!-- TWEAKS TAB -->
                <TabItem Header="Tweaks">
                    <ScrollViewer Background="#101218">
                        <StackPanel Margin="8">

                            <Border Background="#171C26" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Performance &amp; Services"
                                               FontWeight="Bold"
                                               FontSize="15"
                                               Margin="0,0,0,4"/>
                                    <TextBlock Text="Servizi, scheduler, power plan."
                                               Foreground="#D1D5DB"
                                               Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkServicesBase" Content="Servizi base" Margin="0,0,0,6"/>
                                    <CheckBox Name="ChkServicesInsane" Content="Servizi INSANE" Margin="0,0,0,6"/>
                                    <CheckBox Name="ChkPower" Content="Power / Scheduler" Margin="0,0,0,2"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#171C26" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Visual &amp; UX"
                                               FontWeight="Bold"
                                               FontSize="15"
                                               Margin="0,0,0,4"/>
                                    <TextBlock Text="Animazioni, privacy, shell."
                                               Foreground="#D1D5DB"
                                               Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkVisual" Content="Visual tweaks" Margin="0,0,0,6"/>
                                    <CheckBox Name="ChkPrivacy" Content="Privacy tweaks" Margin="0,0,0,2"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#171C26" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Network &amp; Input"
                                               FontWeight="Bold"
                                               FontSize="15"
                                               Margin="0,0,0,4"/>
                                    <TextBlock Text="TCP/IP, adattatore, input, USB."
                                               Foreground="#D1D5DB"
                                               Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkNetCommon" Content="Network common" Margin="0,0,0,6"/>
                                    <CheckBox Name="ChkNetAdapter" Content="Network adapter" Margin="0,0,0,6"/>
                                    <CheckBox Name="ChkInput" Content="Input tweaks" Margin="0,0,0,6"/>
                                    <CheckBox Name="ChkUsb" Content="USB tweaks" Margin="0,0,0,2"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#171C26" CornerRadius="8" Padding="12" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Text="Fortnite"
                                               FontWeight="Bold"
                                               FontSize="15"
                                               Margin="0,0,0,4"/>
                                    <TextBlock Text="Ottimizzazioni specifiche solo per Fortnite."
                                               Foreground="#D1D5DB"
                                               Margin="0,0,0,8"/>
                                    <CheckBox Name="ChkFortnite" Content="Fortnite specific tweaks" Margin="0,0,0,2"/>
                                </StackPanel>
                            </Border>

                        </StackPanel>
                    </ScrollViewer>
                </TabItem>
            </TabControl>

            <!-- Footer -->
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

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Prendo i controlli principali
$RbSafe = $window.FindName("RbSafe")
$RbInsane = $window.FindName("RbInsane")
$RbCustom = $window.FindName("RbCustom")

$TxtModeLabel = $window.FindName("TxtModeLabel")
$TxtModeChip = $window.FindName("TxtModeChip")
$ModeChipBorder = $window.FindName("ModeChipBorder")
$TxtPresetDescription = $window.FindName("TxtPresetDescription")
$TxtStatus = $window.FindName("TxtStatus")
$BtnApply = $window.FindName("BtnApply")

$ChkServicesBase = $window.FindName("ChkServicesBase")
$ChkServicesInsane = $window.FindName("ChkServicesInsane")
$ChkPower = $window.FindName("ChkPower")
$ChkVisual = $window.FindName("ChkVisual")
$ChkPrivacy = $window.FindName("ChkPrivacy")
$ChkNetCommon = $window.FindName("ChkNetCommon")
$ChkNetAdapter = $window.FindName("ChkNetAdapter")
$ChkInput = $window.FindName("ChkInput")
$ChkUsb = $window.FindName("ChkUsb")
$ChkFortnite = $window.FindName("ChkFortnite")

function Set-ModeDisplay {
    if ($RbSafe.IsChecked) {
        $TxtModeLabel.Text = "Mode: SAFE"
        $TxtModeChip.Text = "SAFE"
        $ModeChipBorder.Background = "#0F766E"
        $TxtPresetDescription.Text = "SAFE: preset equilibrato per gaming e uso quotidiano."
    }
    elseif ($RbInsane.IsChecked) {
        $TxtModeLabel.Text = "Mode: INSANE"
        $TxtModeChip.Text = "INSANE"
        $ModeChipBorder.Background = "#B91C1C"
        $TxtPresetDescription.Text = "INSANE: preset aggressivo per prestazioni massime e latenza ridotta."
    }
    else {
        $TxtModeLabel.Text = "Mode: CUSTOM"
        $TxtModeChip.Text = "CUSTOM"
        $ModeChipBorder.Background = "#4B5563"
        $TxtPresetDescription.Text = "CUSTOM: applica solo le checkbox selezionate manualmente."
    }
}

function Set-SafePreset {
    $ChkServicesBase.IsChecked = $true
    $ChkServicesInsane.IsChecked = $false
    $ChkPower.IsChecked = $true
    $ChkVisual.IsChecked = $true
    $ChkPrivacy.IsChecked = $true
    $ChkNetCommon.IsChecked = $true
    $ChkNetAdapter.IsChecked = $true
    $ChkInput.IsChecked = $true
    $ChkUsb.IsChecked = $true
    $ChkFortnite.IsChecked = $false
    $TxtStatus.Text = "Preset SAFE caricato."
}

function Set-InsanePreset {
    $ChkServicesBase.IsChecked = $true
    $ChkServicesInsane.IsChecked = $true
    $ChkPower.IsChecked = $true
    $ChkVisual.IsChecked = $true
    $ChkPrivacy.IsChecked = $true
    $ChkNetCommon.IsChecked = $true
    $ChkNetAdapter.IsChecked = $true
    $ChkInput.IsChecked = $true
    $ChkUsb.IsChecked = $true
    $ChkFortnite.IsChecked = $true
    $TxtStatus.Text = "Preset INSANE caricato."
}

function Set-CustomPreset {
    $TxtStatus.Text = "Modalità CUSTOM attiva."
}

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

$BtnApply.Add_Click({
    $selected = @()

    if ($ChkServicesBase.IsChecked) { $selected += "Servizi base" }
    if ($ChkServicesInsane.IsChecked) { $selected += "Servizi INSANE" }
    if ($ChkPower.IsChecked) { $selected += "Power/Scheduler" }
    if ($ChkVisual.IsChecked) { $selected += "Visual" }
    if ($ChkPrivacy.IsChecked) { $selected += "Privacy" }
    if ($ChkNetCommon.IsChecked) { $selected += "Network common" }
    if ($ChkNetAdapter.IsChecked) { $selected += "Network adapter" }
    if ($ChkInput.IsChecked) { $selected += "Input" }
    if ($ChkUsb.IsChecked) { $selected += "USB" }
    if ($ChkFortnite.IsChecked) { $selected += "Fortnite" }

    if ($selected.Count -eq 0) {
        $TxtStatus.Text = "Nessun tweak selezionato."
        [System.Windows.MessageBox]::Show("Non hai selezionato nessun tweak.", "TedeTweak") | Out-Null
        return
    }

    $TxtStatus.Text = "Selezionati: " + ($selected -join ", ")
    [System.Windows.MessageBox]::Show("Tweaks selezionati:`n`n" + ($selected -join "`n"), "TedeTweak") | Out-Null
})

Set-ModeDisplay
Set-SafePreset

$null = $window.ShowDialog()
