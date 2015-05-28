#todo: if some variable is null or empty
$username = "fenwick-t";
$repo = "MyRepo1";
$branch = "tempBranch";
$path = "runbooks";

#temporary storage to save files
#todo: if folder doesn't exist
$tempStorage = "C:\GithubRunbooksStorage\";

# headers parameters
$token = "1de89fc96275fe1f76683502a1830fe881ea504f";
$headers = @{"Authorization" = "token $token"};

$Uri = "https://api.github.com/repos/$username/$repo/git/refs/heads/$branch";
$jsonResults = invoke-WebRequest -Method Get -Uri $Uri -Headers $headers;
$results = ConvertFrom-Json $jsonResults;

#todo: if somre request is wrong

$branchSha = $results.object.sha;
$Uri = "https://api.github.com/repos/$username/$repo/commits?sha=$branchSha";
$jsonResults = invoke-WebRequest -Method Get -Uri $Uri -Headers $headers;
$commits = ConvertFrom-Json $jsonResults;
#tree's sha from the last commit
$commitSha = $commits[0].sha;

$commits[0]

$Uri = "https://api.github.com/repos/$username/$repo/git/trees/$commitSha";
$jsonBranchTreeData = invoke-WebRequest -Method Get -Uri $Uri -Headers $headers;
$branchTreeData = ConvertFrom-Json $jsonBranchTreeData;
foreach ($item in $branchTreeData.tree)
{
    if (($item.path -eq "runbooks") -and ($item.type -eq "tree"))
    {
        $folderSha = $item.sha;
        break
    }
}

#todo: recursively go through the tree
$Uri = "https://api.github.com/repos/$username/$repo/git/trees/$folderSha";
$jsonFolderTreeData = invoke-WebRequest -Method Get -Uri $Uri -Headers $headers;
$folderTreeData = ConvertFrom-Json $jsonFolderTreeData;
foreach ($item in $folderTreeData.tree)
{
    if ($item.type -eq "blob")
    {
        $destination = $tempStorage + $item.path;
        Invoke-WebRequest $item.url -OutFile $destination;
    }
}

