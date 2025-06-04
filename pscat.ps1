class pscat
{
    [String]         $Address
    [String]         $Port
    [String]         $Command
    [Text.Encoding]  $Encoding
    [PSCustomObject] $Objects
    [Object[]]       $Streams

    powercat ([String] $Address, [String] $Port)
    {
        $this.Address                   = $Address
        $this.Port                      = $Port
        $this.Command                   = ""
        $this.Encoding                  = [Text.Encoding]::ASCII
        $this.Objects                   = [PSCustomObject] @{
            TcpClient                   = $null
            Process                     = $null
        }
        $this.Streams                   = @()
    }
}