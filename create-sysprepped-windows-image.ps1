# Copyright 2016 Cloudbase Solutions Srl
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
$ErrorActionPreference = "Stop"

$osList=@("2019std")
$imageType="KVM"

$scriptPath ="C:\apps\Cloudbase\windows-openstack-imaging-tools"
if(!(Test-Path "$scriptPath" -EA 0)){
	& C:\apps\git\bin\git.exe clone https://github.com/hybridadmin/windows-openstack-imaging-tools.git $scriptPath
}

& C:\apps\git\bin\git.exe -C $scriptPath submodule update --init
if ($LASTEXITCODE) {
    throw "Failed to update git modules."
}

try {
    Join-Path -Path $scriptPath -ChildPath "\WinImageBuilder.psm1" | Remove-Module -ErrorAction SilentlyContinue
    Join-Path -Path $scriptPath -ChildPath "\Config.psm1" | Remove-Module -ErrorAction SilentlyContinue
    Join-Path -Path $scriptPath -ChildPath "\UnattendResources\ini.psm1" | Remove-Module -ErrorAction SilentlyContinue
} finally {
    Join-Path -Path $scriptPath -ChildPath "\WinImageBuilder.psm1" | Import-Module
    Join-Path -Path $scriptPath -ChildPath "\Config.psm1" | Import-Module
    Join-Path -Path $scriptPath -ChildPath "\UnattendResources\ini.psm1" | Import-Module
}

Foreach($os in $osList){

	$osVer=$os.Substring(0,4)
	$edition=($os -replace "$osVer","").ToUpper()

	Switch -Regex ($osVer){
		"2012" 	{ $arch="R2_x64" }
		default { $arch="x64" }	
	}
	
	$vhdName='VPS_WinSrv_{0}_{1}_{2}_Gen2.vhdx' -f $osVer, $arch, $edition
	if($imageType -eq "KVM"){ $vhdExtension="qcow2" }else{ $vhdExtension="vhdx" }
	
	# The Windows image file path that will be generated
	$virtualDiskPath = "E:\Temp\vhdCache\${vhdName}-image.${vhdExtension}"

	# The wim file path is the installation image on the Windows ISO
	$wimFilePath = "E:\Temp\wim\${os}\sources\install.wim"

	# Download the VirtIO drivers ISO from Fedora
	if($imageType -eq "KVM"){
		# VirtIO ISO contains all the synthetic drivers for the KVM hypervisor
		$virtIOISOPath = "E:\Temp\vhdCache\virtio.iso"
		$virtIODownloadLink = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.171-1/virtio-win-0.1.171.iso"

		if(!(Test-Path "$virtIOISOPath" -EA 0)){
			(New-Object System.Net.WebClient).DownloadFile($virtIODownloadLink, $virtIOISOPath)
		}
	}

	# Extra drivers path contains the drivers for the baremetal nodes
	# Examples: Chelsio NIC Drivers, Mellanox NIC drivers, LSI SAS drivers, etc.
	# The cmdlet will recursively install all the drivers from the folder and subfolders
	$extraDriversPath = "C:\drivers\"

	# Every Windows ISO can contain multiple Windows flavors like Core, Standard, Datacenter
	# Usually, the second image version is the Standard one
	$image = (Get-WimFileImagesInfo -WimFilePath $wimFilePath)[0]

	# The path were you want to create the config fille
	$configFilePath = Join-Path $scriptPath "Examples\config.ini"
	New-WindowsImageConfig -ConfigFilePath $configFilePath

	#This is an example how to automate the image configuration file according to your needs
	Set-IniFileValue -Path $configFilePath -Section "Default" -Key "wim_file_path" -Value $wimFilePath
	Set-IniFileValue -Path $configFilePath -Section "Default" -Key "image_name" -Value $image.ImageName
	Set-IniFileValue -Path $configFilePath -Section "Default" -Key "image_path" -Value $virtualDiskPath
	Set-IniFileValue -Path $configFilePath -Section "Default" -Key "virtual_disk_format" -Value "${vhdExtension}"
	Set-IniFileValue -Path $configFilePath -Section "Default" -Key "image_type" -Value "${imageType}"
	Set-IniFileValue -Path $configFilePath -Section "Default" -Key "enable_custom_wallpaper" -Value "False"
	Set-IniFileValue -Path $configFilePath -Section "vm" -Key "disk_size" -Value (30GB)
	if($imageType -eq "KVM"){
		Set-IniFileValue -Path $configFilePath -Section "drivers" -Key "virtio_iso_path" -Value $virtIOISOPath		
		Set-IniFileValue -Path $configFilePath -Section "sysprep" -Key "disable_swap" -Value "True"
	}
	Set-IniFileValue -Path $configFilePath -Section "drivers" -Key "drivers_path" -Value $extraDriversPath
	Set-IniFileValue -Path $configFilePath -Section "updates" -Key "install_updates" -Value "True"
	Set-IniFileValue -Path $configFilePath -Section "updates" -Key "purge_updates" -Value "False"	

	# This scripts generates a raw image file that, after being started as an instance and
	# after it shuts down, it can be used with Ironic or KVM hypervisor in OpenStack.
	New-WindowsCloudImage -ConfigFilePath $configFilePath
	
	if(Test-Path $virtualDiskPath){
		Rename-Item -Path $configFilePath -NewName "config.ini-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
	}
}
