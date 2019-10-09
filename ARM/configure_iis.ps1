# Install IIS.
dism /online /enable-feature /featurename:IIS-WebServerRole

# Set the home page.
Set-Content `
  -Path "C:\\inetpub\\wwwroot\\Default.htm" `
  -Value "<html><body><h1>Welcome to Azure! My name is $($env:computername).</h1></body></html>"
  -Value "<html><body><h3>Hope you enjoy the website.</h3></body></html>"