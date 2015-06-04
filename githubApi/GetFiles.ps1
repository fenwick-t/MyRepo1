<#
.SYNOPSIS 
    Syncs all runbooks in a given GitHub folder to an Azure Automation account.
    
.PARAMETER Repo
    Name of the repository that contains the folder with runbooks to sync

.PARAMETER OAuthToken
    OAuthorization token to have an access to user's GitHub account

.PARAMETER Branch
    Optional name of the GitHub branch to retrieve the runbooks from. Defaults to "master"

.PARAMETER FolderPath
    Optional path to the folder in the GitHub branch to retrieve the runbooks from. Defaults to "runbooks"
#>

workflow Sync-GitHubRunbooks
{
    param (
       [Parameter(Mandatory=$True)]
       [string] $Repo,

       [Parameter(Mandatory=$True)]
       [string] $OAuthToken,

       [Parameter(Mandatory=$False)]
       [string] $Branch = "master",

       [Parameter(Mandatory=$False)]
       [string] $FolderPath = "runbooks"
    )

    $psExtension = ".ps1"

    # headers parameters
    $headers = @{"Authorization" = "token $OAuthToken"};
    
    # get username
    $jsonMetadata = Invoke-WebRequest -Method Get -Uri "https://api.github.com/user" -Headers $headers;
    $metadata = ConvertFrom-Json $jsonMetadata;
    $username = $metadata.login;

    # get branch sha
    $Uri = "https://api.github.com/repos/$username/$Repo/git/refs/heads/$Branch";
    $jsonResults = invoke-WebRequest -Method Get -Uri $Uri -Headers $headers;
    $results = ConvertFrom-Json $jsonResults;
    $branchSha = $results.object.sha;

    #get sha of the last commit from this branch
    $Uri = "https://api.github.com/repos/$username/$Repo/commits?sha=$branchSha";
    $jsonResults = invoke-WebRequest -Method Get -Uri $Uri -Headers $headers;
    $commits = ConvertFrom-Json $jsonResults;    
    $commitSha = $commits[0].sha;

    # get sha of branch's tree
    $Uri = "https://api.github.com/repos/$username/$Repo/git/trees/$commitSha";
    $jsonResults = invoke-WebRequest -Method Get -Uri $Uri -Headers $headers;
    $treeData = ConvertFrom-Json $jsonResults;

    # todo: break if found
    $folderSha = $null;
    foreach ($item in $treeData.tree)
    {
        if (($item.path -eq $FolderPath) -and ($item.type -eq "tree"))
        {
            $folderSha = $item.sha;
        }
    }

    # get sha of folder's tree
    $Uri = "https://api.github.com/repos/$username/$Repo/git/trees/$folderSha";
    $jsonResults = invoke-WebRequest -Method Get -Uri $Uri -Headers $headers;
    $folderTreeData = ConvertFrom-Json $jsonResults;

    # get all runbooks from the folder
    # todo: open inner folders
    foreach ($item in $folderTreeData.tree)
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
            $Uri = "https://api.github.com/repos/$username/$Repo/git/blobs/$itemSha";
            $jsonResults = invoke-WebRequest -Method Get -Uri $Uri -Headers $headers;
            $blobData = ConvertFrom-Json $jsonResults;
            
            InlineScript {
                $content = $Using:blobData.content;
                $bytes = [System.Convert]::FromBase64String($content);
                $runbookDefinition = [System.Text.Encoding]::UTF8.GetString($bytes);
                $Using:runbookName
                $runbookDefinition  
            }
        }
    }
}

Sync-GitHubRunbooks -Repo "MyRepo1" -OAuthToken "." -Branch "tempBranch"
#empty repo error
# Sync-GitHubRunbooks -Repo "TempRepo" -OAuthToken "." -Branch "tempBranch"
# Sync-GitHubRunbooks -Repo "WrongNameRepo" -OAuthToken "." -Branch "tempBranch"

