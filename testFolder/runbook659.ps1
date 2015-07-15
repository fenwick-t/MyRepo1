<#
.SYNOPSIS 
    Runbook for source control feature. Syncs all runbooks from the certain GitHub folder to an Azure Automation account.
.DESCRIPTION 
    This runbook takes connection data and OAuth token from variables in the user's account (but they are created by Automation), gets the Github metadata 
    with Github API and Github Tree API, stores name and definition of every file that matches runbook extension to the hashtable (by default not including subfolders)
    and then saves the runbook to the Automation account using Set-AutomationRunbook activity. If some request while getting the metadata fails, runbook sleeps
    $DelayInSeconds seconds and try to do all requests again.
.PARAMETER Retries
    Optional. Number of retries of requests to the Github to fetch metadata.
.PARAMETER DelayInSeconds
    Optional. Delay between retries of requests to the Github to fetch metadata in seconds.
.PARAMETER SyncSubfolders
    Optional. Boolean value that sync also subfolders
.EXAMPLE 
    Sync-MicrosoftAzureAutomationAccountFromGithubV1 
.EXAMPLE2 
    Sync-MicrosoftAzureAutomationAccountFromGithubV1 -SyncSubfolders
.EXAMPLE3 
    Sync-MicrosoftAzureAutomationAccountFromGithubV1 -Retries 2 -DelayInSeconds 5 -SyncSubfolders
#>
workflow Sync-MicrosoftAzureAutomationAccountFromGithubV1
{
    param (
       [ValidateNotNullOrEmpty()]
       [Parameter(Mandatory=$False)]
       [int] $Retries = 3,

       [ValidateNotNullOrEmpty()]
       [Parameter(Mandatory=$False)]
       [int] $DelayInSeconds = 2,

       [ValidateNotNullOrEmpty()]
       [Parameter(Mandatory=$False)]
       [bool] $SyncSubfolders = $False
    )
    $SourceControlRunbookName = "Sync-MicrosoftAzureAutomationAccountFromGithubV1"
    $SourceControlConnectionVariableName = "Microsoft.Azure.Automation.SourceControl.Connection"
    $SourceControlOAuthTokenVariableName = "Microsoft.Azure.Automation.SourceControl.OAuthToken"

    $InformationalLevel = "Informational"
    $WarningLevel = "Warning"
    $ErrorLevel = "Error"
    $SucceededLevel = "Succeeded"

    $GithubUriGetAuthenticatedUser = "https://api.github.com/user"
    $GithubUriGetReposWithPagination = "https://api.github.com/user/repos?page={0}"
    $GithubUriGetBranch = "https://api.github.com/repos/{0}/{1}/git/refs/heads/{2}"
    $GithubUriGetCommitsToBranch = "https://api.github.com/repos/{0}/{1}/commits?sha={2}"
    $GithubUriGetTreeRecursively = "https://api.github.com/repos/{0}/{1}/git/trees/{2}?recursive=1"
    $GithubUriGetTree = "https://api.github.com/repos/{0}/{1}/git/trees/{2}"
    $GithubUriGetBlob = "https://api.github.com/repos/{0}/{1}/git/blobs/{2}"

    $DuplicateRunbookWarningMessage = "There was a duplicate file with name {0} in the folder {1} or its subfolder. This file will not be synchronized."
    $FileWasNotSyncWebExceptionWarningMessage = "Web-request to Github for accessing the runbook definition failed. The file was not synchronized. Blob sha: {0}."
    $FileWasNotSyncExceptionWarningMessage = "An exception occurred and the file was not synchronized. File's blob sha: {0}."
    $FolderDataTruncatedWarningMessage = "Folder's data is truncated. Some files might not be synchronized"
    $FolderWasNotSyncWebExceptionWarningMessage = "Web-request to Github for accessing the folder tree failed. Folder was not synchronized. Folder tree sha: {0}." 
    $FolderWasNotSyncExceptionWarningMessage = "An exception occurred and the folder was not synchronized. Folder tree sha: {0}"
    $WebExceptionWarningMessage = "Web-request to Github failed. Retrying in {0} seconds"
    $SetAutomationRunbookWarningMessage = "File {0} cannot be saved to the Automation account. Make sure the definition of the file is not empty and is formatted correctly."

    $SourceControlConnectionErrorMessage = "Sync failed. Your Automation account settings have been modified and Automation can no longer connect to your repository. To reconnect your repository, go to the Set Up Source Control blade and enter the credentials for your GitHub account."
    $OAuthTokenErrorMessage =  "Sync failed. Your GitHub token has expired or your Automation account settings have been modified and Automation can no longer connect to your repository. To reconnect your repository, go to the Set Up Source Control blade and enter the credentials for your GitHub account."
    $RepositoryNotFoundErrorMessage = "Sync failed. The specified repository {0} does not exist. Check to see whether the repository has been deleted or if the name has been modified. To reconnect your repository, go to the Set Up Source Control blade, enter the credentials for your GitHub account, and select your repository."
    $BranchNotFoundErrorMessage = "Sync failed. The specified branch {0} does not exist in the current repository {1}. Check to see whether the branch has been deleted or if the name has been modified. To reconnect, go to the Set Up Source Control blade, enter the credentials for your GitHub account, and select your repository and branch."
    $BranchIsEmptyErrorMessage = "Sync failed. The specified branch {0} is empty."
    $FolderNotFoundTruncatedDataErrorMessage = "Sync failed. The number of runbooks in the repository was too large to be retrieved and the runbooks been truncated. Reduce the number of runbooks in the runbooks folder to ensure that all runbooks sync to Azure Automation."
    $FolderNotFoundErrorMessage = "Sync failed. There is no folder with name {0} in current branch {1}."
    $WebExceptionErrorMessage = "Sync failed. WebException occurred. {1}"

    $AllData = Get-PSWorkflowData[Hashtable] -VariableToRetrieve All
	$PsPrivate=$AllData.PsPrivateMetadata
	$SourceControlAccountId = $PsPrivate.AccountId
	$SourceControlJobId =  $psprivate.JobId 

    Function Write-WorkflowTracing
    {
        Param (
            [string] $Level,
            [string] $Message 
        )
        if ($Level -eq $Using:InformationalLevel)
        {
            [Orchestrator.Shared.Shared.TraceEventSource]::Log.SourceControlRunbookInformational($Using:SourceControlRunbookName, $Using:SourceControlAccountId, $Using:SourceControlJobId, $Message)				
        }
        elseif ($Level -eq $Using:WarningLevel)
        {
            [Orchestrator.Shared.Shared.TraceEventSource]::Log.SourceControlRunbookWarning($Using:SourceControlRunbookName, $Using:SourceControlAccountId, $Using:SourceControlJobId, $Message)				
        }
        elseif ($Level -eq $Using:ErrorLevel)
        {
            [Orchestrator.Shared.Shared.TraceEventSource]::Log.SourceControlRunbookError($Using:SourceControlRunbookName, $Using:SourceControlAccountId, $Using:SourceControlJobId, $Message)				
        }
        elseif ($Level -eq $Using:SucceededLevel)
        {
            [Orchestrator.Shared.Shared.TraceEventSource]::Log.SourceControlRunbookSucceeded($Using:SourceControlRunbookName, $Using:SourceControlAccountId, $Using:SourceControlJobId)				
        }
    }

    Write-WorkflowTracing -Level $InformationalLevel -Message "Sync from Github to Azure Automation started. [SyncSubfolders=$SyncSubfolders]"
    Write-Output "Sync started."

    $Retries = [Math]::Max($Retries, 1)
    $Retries = [Math]::Min($Retries, 10)
    $DelayInSeconds = [Math]::Max($DelayInSeconds, 0)
    $DelayInSeconds = [Math]::Min($DelayInSeconds, 100)
    
    Write-Output "Connecting to Github..."

    Write-WorkflowTracing -Level $InformationalLevel -Message "Getting source control parameters from variable Microsoft.Azure.Automation.SourceControl.Connection."
    
    $GithubMetadata = Get-AutomationVariable -Name $SourceControlConnectionVariableName
    if (!$GithubMetadata)
    {
        Write-WorkflowTracing -Level $ErrorLevel -Message "$SourceControlConnectionVariableName variable does not exist. "        
        throw $SourceControlConnectionErrorMessage
    }
    $GithubMetadata = ConvertFrom-Json $GithubMetadata
    $Repo = $GithubMetadata.Repository
    $Branch = $GithubMetadata.Branch
    $FolderPath = $GithubMetadata.RunbookFolderPath

    Write-WorkflowTracing -Level $InformationalLevel -Message "[Repository=$Repo][Branch=$Branch][FolderPath=$FolderPath]"
    Write-WorkflowTracing -Level $InformationalLevel -Message "Getting OAuthToken from encrypted variable Microsoft.Azure.Automation.SourceControl.OAuthToken."
	
    $OAuthToken = Get-AutomationVariable -Name $SourceControlOAuthTokenVariableName
    if (!$OAuthToken)
    {
        Write-WorkflowTracing -Level $ErrorLevel -Message "$SourceControlOAuthTokenVariableName variable does not exist."
        throw $OAuthTokenErrorMessage
    }

    $RunbookInfo = InlineScript
    {
            Function Write-InlineScriptTracing
            {
                Param (
                   [string] $Level,
                   [string] $Message 
                )
                if ($Level -eq $Using:InformationalLevel)
                {
                    [Orchestrator.Shared.Shared.TraceEventSource]::Log.SourceControlRunbookInformational($Using:SourceControlRunbookName, $Using:SourceControlAccountId, $Using:SourceControlJobId, $Message)				
                }
                elseif ($Level -eq $Using:WarningLevel)
                {
                    [Orchestrator.Shared.Shared.TraceEventSource]::Log.SourceControlRunbookWarning($Using:SourceControlRunbookName, $Using:SourceControlAccountId, $Using:SourceControlJobId, $Message)				
                }
                elseif ($Level -eq $Using:ErrorLevel)
                {
                    [Orchestrator.Shared.Shared.TraceEventSource]::Log.SourceControlRunbookError($Using:SourceControlRunbookName, $Using:SourceControlAccountId, $Using:SourceControlJobId, $Message)				
                }
                elseif ($Level -eq $Using:SucceededLevel)
                {
                    [Orchestrator.Shared.Shared.TraceEventSource]::Log.SourceControlRunbookSucceeded($Using:SourceControlRunbookName, $Using:SourceControlAccountId, $Using:SourceControlJobId)				
                }
            }

            # get owner of the Github repository (not necessarily the username - can be an organisation)
            Function Get-Owner
            {
                Param (
                   [string] $OAuthToken,
                   [string] $Repo 
                )
            
                $ErrorActionPreference = 'Stop'
                Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "Get-Owner started."			

                $Headers = @{"Authorization" = "token $OAuthToken"}

                $UsernameResponse = Invoke-RestMethod -Method Get -Uri $Using:GithubUriGetAuthenticatedUser -Headers $Headers
                $Username = $UsernameResponse.Login

                Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "[Username=$Username]"

                # Check if the repository is valid
                $Page = 1
                $RepoObject = $Null
                do
                {
                    Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "Getting repository list. [Username=$Username][RepoListPage=$Page]"
                    
                    $Uri = [string]::Format($Using:GithubUriGetReposWithPagination, $Page)
                    $RepoObjectList = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers
                    $RepoObject = $RepoObjectList.Where({$_.Name -eq $Repo})
                    $Page++
                } while (($RepoObject.name -ne $Repo) -and ($RepoObjectList -ne $Null))
                
                if ($RepoObject)
                {
                    $Owner = $RepoObject.Owner.Login
			        
                    Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "Repository $Repo is valid. Get-Owner is finished successfully. Owner is gotten. [RepositoryOwner=$Owner]"
                }
                else
                {
                    Write-InlineScriptTracing -Level $Using:ErrorLevel -Message "The repository was not found. [Repository=$Repo]"

                    $ErrorString = [string]::Format($Using:RepositoryNotFoundErrorMessage, $Repo)
                    throw $ErrorString
                }

                return $Owner         
            }

            # get the sha of the last commit to the branch (from that data we can get the branch tree data)
            Function Get-LastCommitSha
            {
                Param (
                    [string] $Repo,
                    [string] $OAuthToken,
                    [string] $Owner,
                    [string] $Branch
                )
                $ErrorActionPreference = 'Stop'
                $Headers = @{"Authorization" = "token $OAuthToken"}

                Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "Get-LastCommitSha started. [Owner=$Owner][Repository=$Repo][Branch=$Branch]"

                try
                {
                    # get branch sha
                    $Uri = [string]::Format($Using:GithubUriGetBranch, $Owner, $Repo, $Branch)
                    $Results = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers
                } 
                catch [System.Net.WebException]
                {
                    if ($Error[0].Exception.Message -match "404")
                    {
                        $ErrorMessage = $Error[0].Exception.Message
                        $ErrorType = $Error[0].Exception.GetType().FullName
                        $ErrorStackTrace = $Error[0].Exception.StackTrace
                        $ErrorString = [string]::Format($Using:BranchNotFoundErrorMessage, $Branch, $Repo)
                        throw $ErrorString
                    }
                    else 
                    { 
                        throw 
                    }
                }
                $BranchSha = $Results.Object.Sha

                Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "Branch sha is gotten. [BranchSha=$BranchSha]"
                Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "Getting the sha of the last commit to current branch [Branch=$Branch]"

                # get sha of the last commit from this branch
                $Uri = [string]::Format($Using:GithubUriGetCommitsToBranch, $Owner, $Repo, $BranchSha)
                $Commits = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers
                $LastCommitSha = $Commits[0].Sha
                
                return $LastCommitSha
            }

            # get the sha of the folder that needs to be synced
            Function Get-FolderTreeSha
            {
                Param (
                    [string] $Repo,
                    [string] $OAuthToken,
                    [string] $Owner,
                    [string] $Branch,
                    [string] $FolderPath,
                    [string] $LastCommitSha
                )
                $ErrorActionPreference = 'Stop'
                $Headers = @{"Authorization" = "token $OAuthToken"}
                                
                try
                {
                    # get branch tree data
                    $Uri = [string]::Format($Using:GithubUriGetTreeRecursively, $Owner, $Repo, $LastCommitSha)
                    $TreeData = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers
                }
                catch [System.Net.WebException]
                {
                    if ($Error[0].Exception.Message -match "404")
                    {
                        $ErrorMessage = $Error[0].Exception.Message
                        $ErrorType = $Error[0].Exception.GetType().FullName
                        $ErrorStackTrace = $Error[0].Exception.StackTrace
                        $GithubResponse = ConvertFrom-Json $Error[0]
                        $GithubMessage = $GithubResponse.Message

                        #there are no files and folders in current branch
                        $ErrorString = [string]::Format($Using:BranchIsEmptyErrorMessage, $Branch)
                        throw $ErrorString
                    }
                    else 
                    { 
                        throw 
                    }
                }

                $TreeSize = $TreeData.Tree.Count;
                Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "Tree data was fetched. [TreeSize=$TreeSize]"

                # case if we sync the root folder  
                if ($FolderPath -eq "/")
                {
                    Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "Get-FolderTreeSha finished successfully. Sync folder is root folder. [FolderTreeSha=$TreeData.Sha]"

                    return $TreeData.Sha
                }
               
                # github response does not have a slash as a first symbol in the path name
                $FolderPath = $FolderPath.TrimStart('/')

                Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "Trimmed '/' from the start of FolderPath. [FolderPath=$FolderPath]"

                # get sha of the folder with runbooks
                $FolderTreeSha = $Null            
                $FolderData = $TreeData.Tree.Where({($_.Path -eq $FolderPath) -and ($_.Type -eq "tree")})    
                if (!$FolderData)
                {
                    if ($TreeData.truncated -eq $True)
                    {
                        Write-InlineScriptTracing -Level $Using:ErrorLevel -Message "The specified folder was not found. Github response was truncated. [FolderPath=$FolderPath][Truncated=$TreeData.Truncated]"

                        throw $Using:FolderNotFoundTruncatedDataErrorMessage
                    }
                    else
                    {

                        throw $ErrorString
                    }
                }
                else
                {

                    # get sha of folder's tree
                    $Uri = [string]::Format($Using:GithubUriGetTree, $Owner, $Repo, $FolderData.Sha) 
                    $FolderTreeData = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers
                    $FolderTreeSha = $FolderTreeData.Sha
                }


                return $FolderTreeSha
            }

            # add filename and file definition to hashtable $RbInfo
            Function Sync-File
            {
                Param (
                    [string] $OAuthToken,
                    [string] $Owner,
                    [string] $Repo,
                    $Item,
                    $RbInfo
                )
                $ItemPath = $Item.Path
                $ItemSha = $Item.Sha
                Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "Sync-File started. [RepoOwner=$Owner][Repository=$Repo][ItemPath=$ItemPath][ItemSha=$ItemSha]"

                # get name of the runbook
                $PathSplit = $Item.Path.Split("/")
                $Filename = $PathSplit[$PathSplit.Count - 1]
                $TempPathSplit = $Filename.Split(".")
                $RunbookName = $TempPathSplit[0]
                Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "[RunbookName=$RunbookName]"

                # save content of runbook
                try
                {    
                    $Headers = @{"Authorization" = "token $OAuthToken"}
                    $Uri = [string]::Format($Using:GithubUriGetBlob, $Owner, $Repo, $ItemSha)

                    $BlobData = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers
                          
                    $RunbookSize = $BlobData.Size
                    Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "[RunbookName=$RunbookName][RunbookSize=$RunbookSize]"
  
                    # todo: do not fetch if file size is > 1MB (make a parameter maxSize)
                    $Content = $BlobData.Content
                    $Bytes = [System.Convert]::FromBase64String($Content)
                    $RunbookDefinition = [System.Text.Encoding]::UTF8.GetString($Bytes)
                    
                    if (-not $RbInfo.ContainsKey($RunbookName))
                    {
                        Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "Adding runbook to hashtable. [RunbookName=$RunbookName][RunbookSize=$RunbookSize]"

                        $RbInfo.Add($RunbookName, $RunbookDefinition)
                    }
                    else
                    {
                        $WarningString = [string]::Format($Using:DuplicateRunbookWarningMessage, $RunbookName, $Using:FolderPath)
                        Write-Warning $WarningString
                    }
                }
                catch [System.Net.WebException]
                {
                    $ErrorMessage = $Error[0].Exception.Message
                    $ErrorType = $Error[0].Exception.GetType().FullName
                    $ErrorStackTrace = $Error[0].Exception.StackTrace
                    $GithubResponse = ConvertFrom-Json $Error[0]
                    $GithubMessage = $GithubResponse.Message

                    $WarningString = [string]::Format($Using:FileWasNotSyncWebExceptionWarningMessage, $ItemSha)
                    Write-Warning $WarningString
                    $Error.Clear()
                }
                catch [System.Exception]
                {
                    $ErrorMessage = $Error[0].Exception.Message
                    $ErrorType = $Error[0].Exception.GetType().FullName
                    $ErrorStackTrace = $Error[0].Exception.StackTrace
                    $WarningString = [string]::Format($Using:FileWasNotSyncExceptionWarningMessage, $ItemSha)
                    Write-Warning $WarningString
                    $Error.Clear()
                }

                Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "Sync-File finished successfully. [FileSha=$ItemSha]"
                    
                return $RbInfo         
            }

            # go through the folder (recursively go through all nested folders if $SyncSubfolders == $true) and get runbooks data
            Function Sync-Folder 
            {
                Param (
                    [string] $FolderSha,
                    [string] $OAuthToken,
                    [string] $Owner,
                    [string] $Repo,
                    [bool] $SyncSubfolders,
                    $RbInfo
                )                
                Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "Sync-Folder started. [RepoOwner=$Owner][Repository=$Repo][FolderSha=$FolderSha][SyncSubfolders=$SyncSubfolders]"
                Write-Output "Fetching runbooks..."

                $ErrorActionPreference = 'Stop'
            
                # regex for runbook extension
                $PsExtensionRegex = ".ps1$"
                $AllDataSyncAndNotTruncated = $True
                try
                {
                    $Headers = @{"Authorization" = "token $OAuthToken"}
                    $Uri = [string]::Format($Using:GithubUriGetTree, $Owner, $Repo, $FolderSha)

                    # getting list of items in the folder
                    $FolderData = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers

                    # if it is truncated the only possible way to avoid that is to clone the repository to the local Git. The exact limit of files is unknown but it is certainly more than 1000 files (https://developer.github.com/v3/repos/contents/#get-contents)
                    if ($FolderData.Truncated -eq $True)
                    {
                        Write-InlineScriptTracing -Level $Using:WarningLevel -Message "Folder data is truncated. [FolderSha=$FolderSha]"
                
                        Write-Warning $Using:FolderDataTruncatedWarningMessage
                        $AllDataSyncAndNotTruncated = $False
                    }
                    
                    $FolderSize = $FolderData.Tree.Count
                    Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "[FolderSha=$FolderSha][FolderSize=$FolderSize]"
                    
                    foreach ($Item in $FolderData.Tree)
                    {
                        $ItemSha = $Item.Sha
                        $ItemType = $Item.Type
                        Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "[FolderSha=$FolderSha][ItemSha=$ItemSha][ItemType=$ItemType]"
                    
                        if (($Item.Type -eq "blob") -and ($Item.Path -match $PsExtensionRegex))
                        {
                            # the item is a file with runbook extension
                            $RbInfo = Sync-File -Item $Item -OAuthToken $OAuthToken -Owner $Owner -Repo $Repo -RbInfo $RbInfo
                        }
                        elseif (($Item.Type -eq "tree") -and $SyncSubfolders)
                        {
                            # the item is a folder
                            #TODO: consider stack based recursion (maybe subfolders should be sync before parent folders) and memory storage (we have only about 600 MB)
                            $AllDataSyncAndNotTruncated = $AllDataSyncAndNotTruncated -and (Sync-Folder -FolderSha $Item.Sha -OAuthToken $OAuthToken -Owner $Owner -Repo $Repo -RbInfo $RbInfo -SyncSubfolders $SyncSubfolders)
                        }
                    }
                    $FolderData = $Null
                }
                catch [System.Net.WebException]
                {
                    $AllDataSyncAndNotTruncated = $False

                    $ErrorMessage = $Error[0].Exception.Message
                    $ErrorType = $Error[0].Exception.GetType().FullName
                    $ErrorStackTrace = $Error[0].Exception.StackTrace
                    $GithubResponse = ConvertFrom-Json $Error[0]
                    $GithubMessage = $GithubResponse.Message
                    $WarningString = [string]::Format($Using:FolderWasNotSyncWebExceptionWarningMessage, $FolderSha)
                    Write-Warning $WarningString      
                    $Error.Clear()    
                }
                catch [System.Exception]
                {
                    $AllDataSyncAndNotTruncated = $False

                    $ErrorMessage = $Error[0].Exception.Message
                    $ErrorType = $Error[0].Exception.GetType().FullName
                    $ErrorStackTrace = $Error[0].Exception.StackTrace
                    $WarningString = [string]::Format($Using:FolderWasNotSyncExceptionWarningMessage, $FolderSha)
                    Write-Warning $WarningString
                    $Error.Clear()
                }

                Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "Sync-Folder finished successfully. [RepoOwner=$Owner][Repository=$Repo][FolderSha=$FolderSha][SyncSubfolders=$SyncSubfolders]"
                return $AllDataSyncAndNotTruncated
            }

            Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "[Retries=$Using:Retries][DelayInSeconds=$Using:DelayInSeconds]"
        
            $RetryCount = 0
            $Completed = $False
            $FolderTreeSha = $Null

            while (-not $Completed)
            {
                try
                {
                    $ErrorActionPreference = 'Stop'

                    Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "[RetryCount=$RetryCount]"
                    Write-Output "Searching for the repository..."

                    $Owner = Get-Owner -OAuthToken $Using:OAuthToken -Repo $Using:Repo

                    Write-InlineScriptTracing -Level $Using:InformationalLevel -Message "Owner name is gotten. [RepoOwner=$Owner][Repository=$Using:Repo][Branch=$Using:Branch][FolderPath=$Using:FolderPath]"
                    Write-Output "Searching for the branch..."

                    $LastCommitSha = Get-LastCommitSha -Repo $Using:Repo -OAuthToken $Using:OAuthToken -Owner $Owner -Branch $Using:Branch
Write-Output "Searching for the folder..."

                    $FolderTreeSha = Get-FolderTreeSha -Repo $Using:Repo -OAuthToken $Using:OAuthToken -Owner $Owner -Branch $Using:Branch -FolderPath $Using:FolderPath -LastCommitSha $LastCommitSha
                    $Completed = $True
                     }
                catch [System.Net.WebException]
                {
                    $ErrorMessage = $Error[0].Exception.Message
                    $ErrorType = $Error[0].Exception.GetType().FullName
                    $ErrorStackTrace = $Error[0].Exception.StackTrace
                    $GithubResponse = ConvertFrom-Json $Error[0]
                    $GithubMessage = $GithubResponse.Message

                    $Completed = $True

                    if ($RetryCount -lt $Using:Retries)
                    {
                        $WarningString = [string]::Format($Using:WebExceptionWarningMessage, $Using:DelayInSeconds)
                        Write-Warning $WarningString

                        Start-Sleep $Using:DelayInSeconds
                        $RetryCount++
                        $ErrorActionPreference = 'Continue'
                        $Error.Clear()
                        $Completed = $False
                    }
                    elseif ($ErrorMessage -match "401") {
                        throw $Using:OAuthTokenErrorMessage
                    }
                    else
                    {
                        $ErrorString = [string]::Format($Using:WebExceptionErrorMessage, $GithubMessage)
                        throw $ErrorString
                    }  
                }
                catch [System.Exception]
                {
                    $ErrorMessage = $Error[0].Exception.Message
                    $ErrorType = $Error[0].Exception.GetType().FullName
                    $ErrorStackTrace = $Error[0].Exception.StackTrace

                    throw $ErrorMessage
                    $Completed = $True
                }
            }
    
            $RbInfo = @{}
            if (-not ($FolderTreeSha -eq $Null))
            {      
                # get all runbooks from the folder
                Sync-Folder -folderSha $Using:FolderTreeSha -OAuthToken $Using:OAuthToken -Owner $Using:Owner -Repo $Using:Repo -RbInfo $RbInfo -SyncSubfolders $Using:SyncSubfolders

                # passing rbInfo from InlineScript to workflow
                $RbInfo
            }
    }

    Write-Output "Saving the runbooks to the Automation Account..."

    $ErrorActionPreference = 'Continue'
    foreach ($RbName in $RunbookInfo.Keys) 
    {
        $RbDefinition = $RunbookInfo.$RbName

        Write-WorkflowTracing -Level $InformationalLevel -Message "Saving runbook to the Automation account. [RunbookName=$RbName]"
    
        try
        {
			$RbData = Set-AutomationRunbook -Name $RbName -Definition $RbDefinition -Type "PowerShellWorkflow"
            $RbId = $RbData.RunbookId

            Write-WorkflowTracing -Level $InformationalLevel -Message "The runbook was saved to the Automation account. [RunbookName=$RbName][RunbookId=$RbId]"
		}
		catch
		{
            $WarningString = [string]::Format($SetAutomationRunbookWarningMessage, $RbName)
			Write-Warning $WarningString
		}
    }

    Write-WorkflowTracing -Level $SucceededLevel
    Write-Output "Sync finished successfully"
}