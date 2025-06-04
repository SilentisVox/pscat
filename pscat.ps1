class stream
{
    [String]       $Name
    [IO.Stream]    $IOStream
    [Byte[]]       $Buffer
    [IAsyncResult] $AsyncResult
}

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

    [Bool] Start_Connect()
    {
        Write-Verbose "connecting [$($this.Address)] $($this.Port) ..."
        $TcpClient                      = [Net.Sockets.TcpClient]::new($this.Address, $this.Port)

        if (-not $TcpClient)
        {
            return $false
        }

        $this.Objects.TcpClient         = $TcpClient

        return $true
    }

    [Bool] Start_Listen()
    {
        Write-Verbose "listening on [$($this.Address)] $($this.Port) ..."
        $TcpListener                    = [Net.Sockets.TcpListener]::new($this.Address, $this.Port)
        $TcpListener.Start()
        $TcpClient                      = $TcpListener.AcceptTcpClient()

        $LocalConnectionAddress         = $TcpClient.Client.LocalEndPoint.Address
        $RemoteConnectionAddress        = $TcpClient.Client.RemoteEndPoint.Address
        $RemoteConnectionPort           = $TcpClient.Client.RemoteEndPoint.Port

        Write-Verbose "connect to [$LocalConnectionAddress] from [$RemoteConnectionAddress] $RemoteConnectionPort"

        if (-not $TcpClient)
        {
            return $false
        }

        $TcpListener.Stop()
        $this.Objects.TcpClient         = $TcpClient

        return $true
    }
}