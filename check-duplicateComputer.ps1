<#
Name: check-duplicateComputer
Author: John Fabry - KETS Messaging and Directory Services (MADS) Team
Date: 11/5/2014

Description: Checks to see if there are duplicate computers. This script queries the Global Catalog partition to make a determination.
The script will either accept a command line parameter with the name or will prompt otherwise.
Since it just queries the GC, you don't need any special permission; any authenticated user can run the script.

Requirements: You must be running this from a DOMAIN-JOINED machine, logged in as a DOMAIN USER. Likewise, the machine must have the AD PowerShell module installed, which is attainable via the RSAT.
#>

#Specify the parameter.
param(
    [Parameter(Mandatory=$false,Position=1)]
        [string]$ComputerName
)

#Function to get the local GC.
function Get-LocalGC($root)
{
	#Get the local machine's site name.
	Write-Host "Finding your site..."
	$site = (Get-ADReplicationSite).Name
	
	#Make sure it was successful.
	if($site -ne $null)
	{
		#Query the appropriate GC resource record.
		$GC = (Resolve-DnsName -Name "_gc._tcp.$site._sites.$root" -Type SRV).NameTarget
		
		#Make sure the site has only one GC. If there are multiple, just use the first one!
		if($GC.count -gt 1)
		{
			$GC = $GC[0]
		}
		#Fail if NO GCs are found!
		elseif($GC.count -eq 0)
		{
			Write-Host "`nThere are no local GCs!`n" -ForegroundColor Red
			exit
		}
		
		return $GC
	}
	#Bork if the site name can't be determined for some reason.
	else
	{
		Write-Host "Getting the site failed! The script will exit..." -ForegroundColor Red
		exit
	}
}

#Function to find the root domain.
function Find-RootDomain
{
	#Get the current, full domain in an array.
	$domainArray = $env:userDnsDomain.Split(".")
	
	#Quit if the array only has 2 items since you're already in root!
	if($domainArray.count -eq 2)
	{
		$rootDomain = $env:userDnsDomain
	}
	else
	{
		$tld = $domainArray[$domainArray.count - 1]
		$secondLevelDomain = $domainArray[$domainArray.count - 2]
		$rootDomain = "$secondLevelDomain.$tld"
	}
	return $rootDomain
}

#Main script body.
#Import the AD module to make it a bit friendlier for all systems.
Write-Host "Importing AD module... Please wait.`n"
Import-Module ActiveDirectory

#First check if the parameter was passed. If it was not specified, then the variable is empty string, not $null.
if($ComputerName -eq "")
{
    #Get the computer name from the user.
    $ComputerName = Read-Host "Enter the computer name to query"
}

#Find the root domain.
$localRoot = Find-RootDomain

#Initialize an empty array to house the results; I don't care to dump them to the screen.
$resultArray = @()

#Find the GC.
$localGC = Get-LocalGC($localRoot)

#Make sure it's up.
$isGCUp = Test-Connection -ComputerName $localGC -Count 1 -Quiet
if(!$isGCUp)
{
	Write-Host "`nThe GC is currently unavailable! Please try later..." -ForegroundColor Red
	exit
}

#Re-parse the root to determine the -SearchBase parameter.
$rootArray = $localRoot.Split(".")
$rootTLD = $rootArray[$rootArray.count - 1]
$rootSecondLevel = $rootArray[$rootArray.count - 2]
$searchBase = "DC=$rootSecondLevel,DC=$rootTLD"

#Put this together separately because it won't expand properly if done in the Get-ADComputer cmdlet.
$localGC += ":3268"

#Populate the array with the results, if any.
$resultArray += (Get-ADComputer -Filter {name -eq $ComputerName} -SearchBase $searchBase -SearchScope Subtree -Server $localGC).DistinguishedName

#Count the results and print out if any are found!
#Even if there are no results, PowerShell adds a null value at index 0 with the code above. Check the antithesis to determine if it's empty.
if($resultArray[0] -ne $null)
{
    Write-Host "`nThere were results found! You can't use $ComputerName!" -ForegroundColor Red
    Write-Host "`nThis machine name is being used in the following domain(s):"
    #Print out the domains where the results are found.
    foreach($result in $resultArray)
    {
        #Split the DN to get pieces of the name.
        $placeholder = $result.Split(",")
        #District-level domain is going to be 2 back from the last item in the array.
        $domain = $placeholder[$placeholder.count-3]

        #Check to make sure this isn't OU level in case the name is used in root.
        if($domain.Substring(0,3) -eq "OU=")
        {
            #Switch to using just one back from the end of the placeholder array.
            $domain = $placeholder[$placeholder.Count-2]
        }

        #Split again to remove the "DC="
        $domainMinus = $domain.Split("=")[1]
        Write-Host $domainMinus -ForegroundColor Yellow
    }
	Write-Host ""
	exit
}
else
{
    Write-Host "`nThere were NO results found. You can proceed with using: $ComputerName.`n" -ForegroundColor Green
	exit
}