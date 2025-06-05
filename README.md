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
# or
pscat -l -p 4444

# Connect Mode
pscat -Connect -Address 127.0.0.1 -Port 4444
# or
pscat -c 127.0.0.1 4444

# Pipe process
pscat -Listen -Port 4444 -Execute cmd.exe
# or
pscat -l -p 4444 -e cmd.exe

# Help
pscat -Help
# or
pscat -h
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
