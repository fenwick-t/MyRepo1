workflow Sync-GithubRunbooks
{
    param (
       [Parameter(Mandatory=$True)]
       [ValidateNotNullOrEmpty()]
       [string] $Repo,

       [Parameter(Mandatory=$True)]
       [ValidateNotNullOrEmpty()]
       [string] $OAuthToken,

       [ValidateNotNullOrEmpty()]
       [Parameter(Mandatory=$False)]
       [string] $Organisation,

       [ValidateNotNullOrEmpty()]
       [Parameter(Mandatory=$False)]
       [string] $Branch = "master",

       [ValidateNotNullOrEmpty()]
       [Parameter(Mandatory=$False)]
       [string] $FolderPath = "runbooks",

       [ValidateNotNullOrEmpty()]
       [Parameter(Mandatory=$False)]
       [int] $Retries = 3,

       [ValidateNotNullOrEmpty()]
       [Parameter(Mandatory=$False)]
       [int] $DelayInSeconds = 2
    )

    $runbookInfo = InlineScript
    {
        #TODO: catch Invoke-RestMethod
        # recursively go through all nested folders and get runbooks data
        Function Sync-Folder 
        {
            Param (
            [string] $FolderSha,
            [string] $OAuthToken,
            [string] $Owner,
            [string] $Repo,
            $RbInfo
            )

            $result = $true;
            $headers = @{"Authorization" = "token $OAuthToken"};

            $Uri = "https://api.github.com/repos/" + $Owner + "/" + $Repo + "/git/trees/" + $FolderSha;

            $folderData = Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers;
            if ($folderData.truncated -eq "false")
            {
                $result = $false;
                Write-Verbose "Folder's data is truncated. Some files might not be synchronized"; 
            }
                
            foreach ($item in $folderData.tree)
            {
                if (($item.type -eq "blob") -and ($item.path -match $psExtension))
                {
                    # get name of the runbook
                    $pathSplit = $item.path.Split("/");
                    $filename = $pathSplit[$pathSplit.Count - 1];
                    $tempPathSplit = $filename.Split(".");
                    $runbookName = $tempPathSplit[0];

                    # get content of runbook
                    $itemSha = $item.sha;
                    $Uri = "https://api.github.com/repos/$Owner/$Repo/git/blobs/$itemSha";
                    $blobData = Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers;
                            
                    # todo: if file's size is > 2MB (make a parameter maxSize)
                    $content = $blobData.content;
                    $bytes = [System.Convert]::FromBase64String($content);
                    $runbookDefinition = [System.Text.Encoding]::UTF8.GetString($bytes);
                    $runbookSize = $blobData.size;

                    Write-Verbose "Adding $runbookName with definition $runbookDefinition to hashtable. Size: $runbookSize"
                    $RbInfo.Add($runbookName, $runbookDefinition);
                }
                elseif ($item.type -eq "tree")
                {
                    $result = $result -and (Sync-Folder -FolderSha $item.sha -OAuthToken $OAuthToken -owner $Owner -Repo $Repo -RbInfo $RbInfo)
                }
            }
                
            Return $result;
        }

        $retryCount = 0;
        $completed = $false;
        $folderTreeData = $null;

        while (-not $completed)
        {
            try
            {
                $ErrorActionPreference = 'Stop';

                # regex for .ps1 extension
                $psExtension = ".ps1$"

                # headers parameters
                $headers = @{"Authorization" = "token $Using:OAuthToken"};

                # get owner
                $metadata = Invoke-RestMethod -Method Get -Uri "https://api.github.com/user" -Headers $headers;
                $owner = $metadata.login;

                # if there is no organisation, parameter Organisation should be null or equal to user's login
                if (-not ($Using:Organisation -eq $null) -and -not ($owner -eq $Using:Organisation))
                {
                    Write-Verbose "Organisation $Using:Organisation is used"
                    $owner = $Using:Organisation
                }

                # get branch sha
                $Uri = "https://api.github.com/repos/" + $owner + "/" + $Using:Repo + "/git/refs/heads/" + $Using:Branch;
                $results = Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers;
                $branchSha = $results.object.sha;

                # get sha of the last commit from this branch
                $Uri = "https://api.github.com/repos/" + $owner + "/" + $Using:Repo + "/commits?sha=" + $branchSha;
                $commits = Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers;
                $commitSha = $commits[0].sha;

                # get sha of branch's tree
                $Uri = "https://api.github.com/repos/" + $owner + "/" + $Using:Repo + "/git/trees/" + $commitSha;
                $treeData = Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers;
               
                #get sha of the folder with runbooks
                $folderSha = $null;
                for ($i = 0; ($i -lt $treeData.tree.Count) -and ($folderSha -eq $null); $i++)
                {
                    $item = $treeData.tree[$i];
                    if (($item.path -eq $Using:FolderPath) -and ($item.type -eq "tree"))
                    {
                        $folderSha = $item.sha;
                    }
                    $item = $null;
                }

                if ($folderSha -eq $null)
                {
                    Write-Verbose "There is no folder with name $Using:FolderPath in current branch $Using:Branch."
                }
                else
                {
                    # get sha of folder's tree
                    $Uri = "https://api.github.com/repos/" + $owner + "/" + $Using:Repo + "/git/trees/" + $folderSha;
                    $folderTreeData = Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers;
                }

                $completed = $true;
            }
            catch [Exception]
            {
                if ($retryCount -lt $Using:Retries)
                {
                    Write-Verbose "Web-request to Github failed. Retrying in $Using:DelayInSeconds second";
                    Start-Sleep $Using:DelayInSeconds
                    $retryCount++
                    #TODO: do I need this?
                    $ErrorActionPreference = 'Continue';
                }
                else
                {
                    Write-Verbose "Web-request to Github failed max number of times";
                    $errorMessage = $Error[0]
                    Write-Verbose "Error: $errorMessage"
                    $completed = $true;                    
                }
                $Error.Clear()
            }
        }
    
        $RbInfo = @{};
        if (-not ($folderTreeData -eq $null))
        {      
            # get all runbooks from the folder
            Sync-Folder -folderSha $Using:folderTreeData.sha -OAuthToken $Using:OAuthToken -owner $Using:owner -Repo $Using:Repo -RbInfo $RbInfo;
            $RbInfo
        }
    }

    foreach ($rbName in $runbookInfo.Keys) 
    {
        $rbDefinition = $runbookInfo.$rbName
        Write-Verbose "Trying to save $rbName to the database. definition $rbDefinition"
        #Set-AutomationRunbook -Name $rbName -Definition $rbDefinition
    }
    Write-Verbose "Sync is finished"
}
