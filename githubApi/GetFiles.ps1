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
    
    # get username by token
    $jsonMetadata = Invoke-WebRequest -Method Get -Uri "https://api.github.com/user" -Headers $headers;
    $metadata = ConvertFrom-Json $jsonMetadata;
    $username = $metadata.login;

    $Uri = "https://api.github.com/repos/$username/$repo/git/refs/heads/$branch";
    $jsonResults = invoke-WebRequest -Method Get -Uri $Uri -Headers $headers;
    $results = ConvertFrom-Json $jsonResults;
    $results
}

Sync-GitHubRunbooks -Repo "MyRepo1" -OAuthToken "c601a5a48d5e3d88477be6ff1df343b78da2bd91" -Branch "tempBranch"
