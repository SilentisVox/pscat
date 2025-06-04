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

    [Void] Setup_Streams()
    {
        if ($this.Objects.TcpClient)
        {
            $IOStream                   = $this.Objects.TcpClient.GetStream()
            $ReadBuffer, $ReadOp        = $this.Start_AsyncRead($IOStream)

            $this.Streams              += $this.Make_Stream("TcpStream", $IOStream, $ReadBuffer, $ReadOp)
        }

        if ($this.Objects.Process)
        {
            $IOStream                   = $this.Objects.Process.StandardOutput.BaseStream
            $ReadBuffer, $ReadOp        = $this.Start_AsyncRead($IOStream)

            $this.Streams              += $this.Make_Stream("StdOutStream", $IOStream, $ReadBuffer, $ReadOp)

            $IOStream                   = $this.Objects.Process.StandardError.BaseStream
            $ReadBuffer, $ReadOp        = $this.Start_AsyncRead($IOStream)

            $this.Streams              += $this.Make_Stream("StdErrStream", $IOStream, $ReadBuffer, $ReadOp)
        }
    }

    [String] Process_Streams([Int] $StreamIndex)
    {
        $Stream                         = $this.Streams[$StreamIndex]
        $Data                           = $null

        if ($Stream.AsyncResult.IsCompleted)
        {
            $Length                     = $Stream.IOStream.EndRead($Stream.AsyncResult)

            if ($Length -eq 0)
            {
                return $null
            }

            $Data                       = $this.Encoding.GetString($Stream.Buffer, 0, $Length)
            $ReadBuffer, $ReadOp        = $this.Start_AsyncRead($Stream.IOStream)
            $Stream                     = $this.Make_Stream($Stream.Name, $Stream.IOStream, $ReadBuffer, $ReadOp)
            $this.Streams[$StreamIndex] = $Stream
        }

        return $Data
    }

    [Void] Update_DiagnosticsProcess()
    {
        foreach ($Stream in 0..2)
        {
            $Data                       = $this.Process_Streams($Stream)
            $Bytes                      = $this.Encoding.GetBytes($Data)

            if ($Data -eq $null)
            {
                continue
            }

            if ($Stream -eq 0)
            {
                $this.Objects.Process.StandardInput.BaseStream.Write($Bytes, 0, $Bytes.Length)
                $this.Objects.Process.StandardInput.BaseStream.Flush()
            }
            else
            {
                $this.Streams[0].IOStream.Write($Bytes, 0, $Bytes.Length)
                $this.Streams[0].IOStream.Flush()
            }
        }
    }

    [Void] Update_Console()
    {
        $KeyPressed                     = [Console]::ReadKey($true)
        $CursorPosition                 = [Console]::CursorLeft

        if ($KeyPressed.Key -eq "Enter")
        {
            $this.Command              += "`n"
            $RawCommand                 = $this.Encoding.GetBytes($this.Command)
            $this.Streams[0].IOStream.Write($RawCommand, 0, $RawCommand.Length)
            $this.Streams[0].IOStream.Flush()
            [Console]::WriteLine()
            $this.Command               = ""
        }
        elseif ($KeyPressed.Key -eq "Backspace") 
        {
            if ($this.Command.Length -gt 0) 
            {
                $this.Command           = $this.Command.Substring(0, $this.Command.Length - 1)
                [Console]::SetCursorPosition([Console]::CursorLeft - 1, [Console]::CursorTop)
                [Console]::Write(" ")
                [Console]::SetCursorPosition([Console]::CursorLeft - 1, [Console]::CursorTop)
            }
        }
        else
        {
            $this.Command              += $KeyPressed.KeyChar
            [Console]::Write($KeyPressed.KeyChar)
        }
    }

    [Void] Update_TcpConnection()
    {
        $Data                           = $this.Process_Streams(0)

        if ($Data)
        {
            [Console]::Write($Data)
        }

        if ([Console]::KeyAvailable)
        {
            $this.Update_Console()
        }
    }

    [Void] Close_Streams()
    {
        foreach ($Stream in $this.Streams)
        {
            $Stream.IOStream.Close()
        }

        if ($this.Objects.TcpClient)
        {
            $this.Objects.TcpClient.Close
        }

        if ($this.Objects.Process)
        {
            $this.Objects.Process.Kill()
        }
    }
}