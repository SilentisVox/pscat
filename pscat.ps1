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

    [Bool] Start_DiagnosticsProcess([String] $ProcessName)
    {
        $Info                           = [Diagnostics.ProcessStartInfo]::new()
        $Info.FileName                  = $ProcessName
        $Info.UseShellExecute           = $false
        $Info.RedirectStandardInput     = $true
        $Info.RedirectStandardOutput    = $true
        $Info.RedirectStandardError     = $true
        $Process                        = [Diagnostics.Process]::Start($Info)

        if (-not $Process)
        {
            return $false
        }

        $this.Objects.Process           = $Process

        return $true
    }

    [Object[]] Start_AsyncRead([IO.Stream] $Stream)
    {
        $ReadingBuffer                  = [Byte[]]::new(65535)
        $ReadingOperation               = $Stream.BeginRead($ReadingBuffer, 0, $ReadingBuffer.Length, $null, $null)

        return $ReadingBuffer, $ReadingOperation
    }

    [Stream] Make_Stream([String] $Name, [IO.Stream] $IOStream, [Byte[]] $Buffer, [IAsyncResult] $AsyncResult)
    {
        $Stream                         = [Stream]::new()
        $Stream.Name                    = $Name
        $Stream.IOStream                = $IOStream
        $Stream.Buffer                  = $Buffer
        $Stream.AsyncResult             = $AsyncResult

        return $Stream
    }
}