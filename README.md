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

# Help
pscat -Help # <- Add
```

## **Brief Explanation**

![pscat](assets/pscat.jpg)