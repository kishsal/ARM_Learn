select-subscription

$VNetName  = "VNetData"
$FESubName = "FrontEnd"
$BESubName = "Backend"
$GWSubName = "GatewaySubnet"
$VNetPrefix1 = "192.168.0.0/16"
$VNetPrefix2 = "10.254.0.0/16"
$FESubPrefix = "192.168.1.0/24"
$BESubPrefix = "10.254.1.0/24"
$GWSubPrefix = "192.168.200.0/26"
$VPNClientAddressPool = "172.16.201.0/24"
$ResourceGroup = "VpnGatewayDemo"
$Location = "East US"
$GWName = "VNetDataGW"
$GWIPName = "VNetDataGWPIP"
$GWIPconfName = "gwipconf"

#Create RG
New-AzResourceGroup -Name $ResourceGroup -Location $Location

#Create subnet configurations for the virtual network
$fesub = New-AzVirtualNetworkSubnetConfig -Name $FESubName -AddressPrefix $FESubPrefix
$besub = New-AzVirtualNetworkSubnetConfig -Name $BESubName -AddressPrefix $BESubPrefix
$gwsub = New-AzVirtualNetworkSubnetConfig -Name $GWSubName -AddressPrefix $GWSubPrefix

#create the virtual network using the subnet values and a static DNS server
New-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroup -Location $Location -AddressPrefix $VNetPrefix1,$VNetPrefix2 -Subnet $fesub, $besub, $gwsub -DnsServer 10.2.1.3

#specify the variables for this network that you have just created.
$vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroup
$subnet = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnet

#Request a dynamically assigned public IP address
$pip = New-AzPublicIpAddress -Name $GWIPName -ResourceGroupName $ResourceGroup -Location $Location -AllocationMethod Dynamic
$ipconf = New-AzVirtualNetworkGatewayIpConfig -Name $GWIPconfName -Subnet $subnet -PublicIpAddress $pip


#Create VPN Gateway
New-AzVirtualNetworkGateway -Name $GWName -ResourceGroupName $ResourceGroup `
  -Location $Location -IpConfigurations $ipconf -GatewayType Vpn `
  -VpnType RouteBased -EnableBgp $false -GatewaySku VpnGw1 -VpnClientProtocol "IKEv2"

#Add VPN Client Address Pool
$Gateway = Get-AzVirtualNetworkGateway -ResourceGroupName $ResourceGroup -Name $GWName
Set-AzVirtualNetworkGateway -VirtualNetworkGateway $Gateway -VpnClientAddressPool $VPNClientAddressPool

### Generate Client Certificate

# create the self-signed root certificate
$cert = New-SelfSignedCertificate -Type Custom -KeySpec Signature `
-Subject "CN=P2SRootCert" -KeyExportPolicy Exportable `
-HashAlgorithm sha256 -KeyLength 2048 `
-CertStoreLocation "Cert:\CurrentUser\My" -KeyUsageProperty Sign -KeyUsage CertSign

#generate a client certificate signed by your new root certificate
New-SelfSignedCertificate -Type Custom -DnsName P2SChildCert -KeySpec Signature `
-Subject "CN=P2SChildCert" -KeyExportPolicy Exportable `
-HashAlgorithm sha256 -KeyLength 2048 `
-CertStoreLocation "Cert:\CurrentUser\My" `
-Signer $cert -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.2")

<#
With our certificates generated, we need to export our root certificate's public key.

Run certmgr from PowerShell to open the Certificate Manager.

Navigate to Personal > Certificates. Find and right-click the P2SRootCert certificate in the list and select All tasks > Export....

In the Certificate Export Wizard, click Next.

Ensure that No, do not export the private key is selected, and then click Next.

On the Export File Format page, ensure that Base-64 encoded X.509 (.CER) is selected, and then click Next.

In the File to Export page, under File name, navigate to a location you'll remember and save the file as P2SRootCert.cer, and then click Next.

On the Completing the Certificate Export Wizard page, click Finish.

On the Certificate Export Wizard message box, click OK.
#>

### Upload the root certificate public key information

#to declare a variable for the certificate name
$P2SRootCertName = "P2SRootCert.cer"

#Replace the <cert-path> placeholder with the export location of your root certificate and execute the following command
$filePathForCert = "<cert-path>\P2SRootCert.cer"
$cert = new-object System.Security.Cryptography.X509Certificates.X509Certificate2($filePathForCert)
$CertBase64 = [system.convert]::ToBase64String($cert.RawData)
$p2srootcert = New-AzVpnClientRootCertificate -Name $P2SRootCertName -PublicCertData $CertBase64

#Upload certificate
Add-AzVpnClientRootCertificate -VpnClientRootCertificateName $P2SRootCertName -VirtualNetworkGatewayname $GWName -ResourceGroupName $ResourceGroup -PublicCertData $CertBase64


### Configure the native VPN Client

#create VPN client configuration files in .ZIP format
$profile = New-AzVpnClientConfiguration -ResourceGroupName $ResourceGroup -Name $GWName -AuthenticationMethod "EapTls"
$profile.VPNProfileSASUrl


<#
1) Copy the URL returned in the output from this command and paste it into your browser. Your browser should start downloading a .ZIP file. Extract the archive contents and put them in a suitable location.

Note: Some browsers will initially attempt to block downloading this ZIP file as a dangerous download. You will need to override this in your browser to be able to extract the archive contents.

2) In the extracted folder, navigate to either the WindowsAmd64 folder (for 64-bit Windows computers) or the WindowsX86 folder (for 32-bit computers).

Note: If you want to configure a VPN on a non-Windows machine, you can use the certificate and settings files from the Generic folder.

3) Double-click on the VpnClientSetup{architecture}.exe file, with {architecture} reflecting your architecture.
4) In the Windows protected your PC screen, click More info, and then click Run anyway.
5) In the User Account Control dialog box, click Yes.
6) In the VNetData dialog box, click Yes.

Connect to Azure
1) Press the Windows key, type Settings and press Enter.
2) In the Settings window, click Network and Internet.
3) In the left-hand pane, click VPN.
4) In the right-hand pane, click VNetData, and then click Connect.
5) In the VNetData window, click Connect.
6) In the next VNetData window, click Continue.
7) In the User Account Control message box, click Yes.

 Note: If these steps do not work, you may need to restart your computer.

Verify your connection
1) In a new Windows command prompt, run IPCONFIG /ALL.
2) Copy the IP address under PPP adapter VNetData, or write it down.
3) Confirm that IP address is in the VPNClientAddressPool range of 172.16.201.0/24.
4) You have successfully made a connection to the Azure VPN gateway.

You just set up a VPN gateway, allowing you to make an encrypted client connection to a virtual network in Azure. This approach is great with client computers and smaller site-to-site connections.
#>