Add-Type -AssemblyName PresentationFramework

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="TedeTweak Test"
        Height="320"
        Width="480"
        WindowStartupLocation="CenterScreen"
        Background="#101218"
        Foreground="White">
    <Grid>
        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
            <TextBlock Text="TedeTweak"
                       FontSize="24"
                       FontWeight="Bold"
                       HorizontalAlignment="Center"
                       Margin="0,0,0,12"/>
            <Button Name="BtnTest"
                    Content="Apri test"
                    Width="140"
                    Height="36"
                    Background="#0F766E"
                    Foreground="White"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$BtnTest = $window.FindName("BtnTest")

$BtnTest.Add_Click({
    [System.Windows.MessageBox]::Show("GUI OK", "TedeTweak") | Out-Null
})

$null = $window.ShowDialog()
