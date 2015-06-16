workflow parametersRunbook
{
  [Parameter(Mandatory=$True)]
  [ValidateNotNullOrEmpty()]
  [string] $Name
  Write-Output "Hello $Name"
}
