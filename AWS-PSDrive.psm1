
using namespace Microsoft.PowerShell.SHiPS

$Global:PSDefaultParameterValues['*:Region'] = { if(($pwd -replace "\\","/") -match '^.*/regions/(?<Region>[^/]+)(/.*)*$') { $matches["Region"] } } 

$Global:PSDefaultParameterValues['*-ECS*:Cluster'] = { if(($pwd -replace "\\","/") -match '^.*/ecs/clusters/(?<Cluster>[^/]+)(/.*)*$') { $matches["Cluster"] } } 

[SHiPSProvider(UseCache=$true)]
class Aws : SHiPSDirectory
{
    Aws([string]$name): base($name)
    {        
        
    } 

    [object[]] GetChildItem()
    {
        return @(
            [SSMParamsQuery]::new('regions', '/aws/service/global-infrastructure/regions'),
            [SSMParamsQuery]::new('services', '/aws/service/global-infrastructure/services')
        )
    }
}


$script:serviceCommands = @{
    'autoscaling' = @{
        'auto-scaling-groups' = @{ FunctionName = "Get-ASAutoScalingGroup" };
    };
    'codebuild' = @{
        'builds' = @{ FunctionName = "Get-CBBuildIdList" };
        'projects' = @{ FunctionName = "Get-CBProjectList" };
    };
    'ec2' = @{
        'instances' = @{ FunctionName = "Get-EC2Instance" };
        'security-groups' = @{ FunctionName = "Get-EC2SecurityGroup" };
    };
    'ecr' = @{
        'images' = @{ FunctionName = "Get-ECRImage" };
        'repositories' = @{ FunctionName = "Get-ECRRepository" };        
    };
    'ecs' = @{   
        'clusters' = @{ 
            FunctionName = "Get-ECSClusterList"; 
            ItemKeyGetter = { $args[0].Split(':')[-1] };
            ChildCalls = @{
                'container-instances' = @{ FunctionName = "Get-ECSContainerInstanceList" };        
                'services' = @{ FunctionName = "Get-ECSClusterService" };        
                'tasks' = @{ FunctionName = "Get-ECSTaskList" };
            } 
        };
    };
    'rds' = @{
        'clusters' = @{ FunctionName = "Get-RDSDBCluster" };
        'instances' = @{ FunctionName = "Get-RDSDBInstance" };
        'security-groups' = @{ FunctionName = "Get-RDSDBSecurityGroup" };
    };
    's3' = @{
        'buckets' = @{ FunctionName = "Get-S3Bucket" }
    };
}

function GetServiceFolders([string]$serviceName)
{   
    $stuffForService = $script:serviceCommands[$serviceName]

    if ($stuffForService) {

        return @( $stuffForService.keys | %{ 
            $stuff = $script:serviceCommands[$serviceName][$_]

            [CLICall]::new($_, $stuff.FunctionName, $stuff.FunctionArgs, $stuff.ItemKeyGetter, $stuff.ChildCalls)
        })
    }
    else {
        return @()
    }
}

[SHiPSProvider(UseCache=$true)]
class SSMParamsQuery : SHiPSDirectory
{
    [string]$QueryPath = $null
    
    [string]$regionPatternA = '/aws/service/global-infrastructure/regions/*'
    [string]$servicePatternA = '/aws/service/global-infrastructure/services/*'    
    [string]$servicePatternB = '/aws/service/global-infrastructure/regions/*/services/*'
    [string]$regionPatternB = '/aws/service/global-infrastructure/services/*/regions/*'  
                
    SSMParamsQuery([string]$paramName, [string]$queryPath) : base ($paramName)
    {
        $this.QueryPath = $queryPath
    }    

    [object[]] GetChildItem()
    {   
        $additionalFolders = @()
        $additionalFolders += if ($this.QueryPath -like $this.regionPatternA -and $this.QueryPath -notlike $this.regionPatternA + '/*') { [SSMParamsQuery]::new('services', '' + $this.QueryPath + '/services') }
        $additionalFolders += if ($this.QueryPath -like $this.servicePatternA -and $this.QueryPath -notlike $this.servicePatternA + '/*') { [SSMParamsQuery]::new('regions', '' + $this.QueryPath + '/regions') }

        $additionalFolders += if ($this.QueryPath -like $this.servicePatternA -or $this.QueryPath -like $this.servicePatternB) { GetServiceFolders($this.Name) }

        return $additionalFolders + @(Get-SSMParametersByPath -Path $this.QueryPath | %{ [SSMParamsQuery]::new($_.Value, $_.Name) })
    } 
}

[SHiPSProvider(UseCache=$true)]
class CLICall : SHiPSDirectory
{
    [string]$FunctionName = $null
    [object]$FunctionArgs = $null
    [object]$ItemKeyGetter = $null
    [object]$ChildCalls = $null
                        
    CLICall([string]$paramName, [string]$functionName, [object]$funcArgs, [string]$itemKeyGetter, [object]$childCalls) : base ($paramName)
    {
        $this.FunctionName = $functionName
        $this.FunctionArgs = $funcArgs
        $this.ItemKeyGetter = $itemKeyGetter
        $this.ChildCalls = $childCalls
    }    

    [object[]] GetChildItem()
    {
        $funcArgs = if ($this.FunctionArgs) { $this.FunctionArgs } else { @{} }
        $getter = $this.ItemKeyGetter
        return @( & $this.FunctionName @funcArgs | %{ [CLIItem]::new((& $getter $_), $_, $this.ChildCalls) } )
    }
}


[SHiPSProvider(UseCache=$true)]
class CLIItem : SHiPSDirectory
{
    [object]$Underlying = $null
    [object]$ChildCalls = $null
                    
    CLIItem([string]$paramName, [object]$underlying, [object]$childCalls) : base ($paramName)
    {
        $this.Underlying = $underlying
        $this.ChildCalls = $childCalls
    }    

    [object[]] GetChildItem()
    {   
        $additionalFolders = @()

        if ($this.ChildCalls) {

            return @( $this.ChildCalls.keys | %{ 
                $stuff = $this.ChildCalls[$_]

                $additionalFolders += [CLICall]::new($_, $stuff.FunctionName, $stuff.FunctionArgs, $stuff.ItemKey, $stuff.ChildCalls)
            })
        }

        return $additionalFolders + $this.Underlying
    }
}

