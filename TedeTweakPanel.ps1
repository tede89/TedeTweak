# ==========================
# TedeTweakPanel.ps1 - v0.1
# GUI base WPF (Windows 11)
# ==========================

# Carico l'assembly WPF principale (PresentationFramework) [serve per Window, Grid, ecc.]
Add-Type -AssemblyName PresentationFramework

# Qui definisco il layout della finestra in XAML dentro una stringa multi-linea.
# XAML è il “HTML” di WPF: descrive controlli, griglie, colori, ecc.
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TedeTweak Panel"
        Height="520" Width="900"
        WindowStartupLocation="CenterScreen"
        Background="#111318"
        Foreground="#F5F5F5"
        ResizeMode="CanResizeWithGrip">

    <!-- Grid principale: colonna sinistra per sidebar, colonna destra per contenuto -->
    <Grid Margin="0">
        <Grid.ColumnDefinitions>
            <!-- Sidebar stretta a sinistra -->
            <ColumnDefinition Width="170"/>
            <!-- Contenuto principale che prende il resto -->
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <!-- Una sola riga: la finestra intera -->
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- ================= SIDEBAR SINISTRA ================= -->
        <Border Grid.Column="0" Background="#14161D">
            <StackPanel Margin="12">
                <!-- Logo / titolo piccolo in alto -->
                <TextBlock Text="TedeTweak"
                           FontWeight="Bold"
                           FontSize="18"
                           Margin="0,0,0,16"/>

                <!-- Elementi di navigazione sidebar -->
                <!-- Per ora sono solo estetici, in seguito ci colleghiamo la logica -->
                <Button Name="BtnNavHome"
                        Content="Home"
                        Margin="0,0,0,8"
                        Padding="8"
                        Background="#1D2028"
                        Foreground="#F5F5F5"
                        BorderBrush="#333843"
                        HorizontalContentAlignment="Left"/>

                <Button Name="BtnNavPreset"
                        Content="Preset"
                        Margin="0,0,0,8"
                        Padding="8"
                        Background="#111318"
                        Foreground="#F5F5F5"
                        BorderBrush="#333843"
                        HorizontalContentAlignment="Left"/>

                <Button Name="BtnNavTweaks"
                        Content="Tweaks"
                        Margin="0,0,0,8"
                        Padding="8"
                        Background="#111318"
                        Foreground="#F5F5F5"
                        BorderBrush="#333843"
                        HorizontalContentAlignment="Left"/>

                <Button Name="BtnNavNetwork"
                        Content="Network"
                        Margin="0,0,0,8"
                        Padding="8"
                        Background="#111318"
                        Foreground="#F5F5F5"
                        BorderBrush="#333843"
                        HorizontalContentAlignment="Left"/>

                <Button Name="BtnNavInfo"
                        Content="Info"
                        Margin="0,0,0,8"
                        Padding="8"
                        Background="#111318"
                        Foreground="#F5F5F5"
                        BorderBrush="#333843"
                        HorizontalContentAlignment="Left"/>
            </StackPanel>
        </Border>

        <!-- ============== CONTENUTO PRINCIPALE (DESTRA) ============== -->
        <Grid Grid.Column="1" Margin="12">
            <Grid.RowDefinitions>
                <!-- Riga header in alto -->
                <RowDefinition Height="Auto"/>
                <!-- Riga corpo (tab) -->
                <RowDefinition Height="*"/>
                <!-- Riga footer (Apply + log) -->
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- HEADER -->
            <DockPanel Grid.Row="0" LastChildFill="False" Margin="0,0,0,8">
                <!-- Titolo grande a sinistra -->
                <StackPanel DockPanel.Dock="Left" Orientation="Vertical">
                    <TextBlock Text="TedeTweak Panel"
                               FontSize="22"
                               FontWeight="Bold"/>
                    <TextBlock Name="TxtModeLabel"
                               Text="Mode: SAFE"
                               FontSize="13"
                               Foreground="#A0A4B8"
                               Margin="0,4,0,0"/>
                </StackPanel>

                <!-- Badgetto modalità a destra -->
                <Border DockPanel.Dock="Right"
                        Background="#2563EB"
                        CornerRadius="999"
                        Padding="10,4"
                        VerticalAlignment="Center">
                    <TextBlock Name="TxtModeChip"
                               Text="SAFE"
                               FontSize="12"
                               FontWeight="SemiBold"
                               Foreground="White"/>
                </Border>
            </DockPanel>

            <!-- CORPO: TabControl per Preset / Tweaks / Network (interno) -->
            <TabControl Grid.Row="1"
                        Name="MainTab"
                        Background="#111318"
                        BorderBrush="#2A303C"
                        Margin="0,0,0,8">
                <!-- TAB PRESET -->
                <TabItem Header="Preset">
                    <Grid Background="#111318" Margin="4">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="2*"/>
                            <ColumnDefinition Width="3*"/>
                        </Grid.ColumnDefinitions>

                        <!-- Colonna sinistra: scelta preset -->
                        <StackPanel Grid.Column="0" Margin="0,0,12,0">
                            <TextBlock Text="Modalità"
                                       FontWeight="SemiBold"
                                       Margin="0,0,0,6"/>
                            <!-- Radio buttons SAFE / INSANE / CUSTOM -->
                            <StackPanel>
                                <RadioButton Name="RbSafe"
                                             Content="SAFE (Consigliato)"
                                             IsChecked="True"
                                             Margin="0,0,0,4"/>
                                <RadioButton Name="RbInsane"
                                             Content="INSANE (Tryhard)"
                                             Margin="0,0,0,4"/>
                                <RadioButton Name="RbCustom"
                                             Content="CUSTOM (usa solo le checkbox)"
                                             Margin="0,0,0,8"/>
                            </StackPanel>

                            <Separator Margin="0,4,0,8"/>

                            <TextBlock Text="Rete" FontWeight="SemiBold" Margin="0,0,0,6"/>
                            <ComboBox Name="CmbNetMode" SelectedIndex="0" Margin="0,0,0,8">
                                <ComboBoxItem Content="LAN / Ethernet"/>
                                <ComboBoxItem Content="Wi-Fi"/>
                            </ComboBox>

                            <TextBlock Text="CPU" FontWeight="SemiBold" Margin="0,0,0,6"/>
                            <ComboBox Name="CmbCpu" SelectedIndex="0" Margin="0,0,0,8">
                                <ComboBoxItem Content="AMD Ryzen"/>
                                <ComboBoxItem Content="Intel Core"/>
                            </ComboBox>

                            <TextBlock Text="GPU" FontWeight="SemiBold" Margin="0,0,0,6"/>
                            <ComboBox Name="CmbGpu" SelectedIndex="1" Margin="0,0,0,8">
                                <ComboBoxItem Content="AMD Radeon"/>
                                <ComboBoxItem Content="NVIDIA GeForce"/>
                                <ComboBoxItem Content="Intel Arc"/>
                            </ComboBox>
                        </StackPanel>

                        <!-- Colonna destra: descrizione preset / futuro riepilogo -->
                        <Border Grid.Column="1"
                                Background="#151822"
                                CornerRadius="8"
                                Padding="12">
                            <StackPanel>
                                <TextBlock Text="Descrizione preset"
                                           FontWeight="SemiBold"
                                           Margin="0,0,0,4"/>
                                <TextBlock Name="TxtPresetDescription"
                                           Text="SAFE: servizi base, power plan, network, gaming, senza modifiche troppo aggressive."
                                           TextWrapping="Wrap"
                                           Foreground="#C5C9D7"/>
                            </StackPanel>
                        </Border>
                    </Grid>
                </TabItem>

                <!-- TAB TWEAKS -->
                <TabItem Header="Tweaks">
                    <ScrollViewer Background="#111318">
                        <StackPanel Margin="4" 
