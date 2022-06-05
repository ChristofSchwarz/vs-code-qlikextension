# Auto-upload Qlik Sense extension from Visual Studio Code

Environment: Windows

### In either case you need
- "Run on Save" extension in Visual Studio Code

### If you upload to Qlik Cloud, you need
- Qlik CLI from https://qlik.dev/tutorials/get-started-with-qlik-cli
- API key for your user

### If you upload to Qlik Sense Windows you need
- access via QRS API port 4242
- the client certificate in PFX format
- PowerShell 7 if your Qlik Sense server certificate is not a public one*

*only PowerShell 7 has the option to ignore an invalid certificate. PowerShell 7 can be installed alongside with your current Windows' PowerShell 
version, they can coexist.

