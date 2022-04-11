Get-PSDrive 'AWS' | Remove-PSDrive -Force

Remove-Module AWS-PSDrive

Import-Module .\

New-PSDrive -Name 'AWS' -PSProvider SHiPS -Root AWS-PSDrive#Aws

 
$thing = @{ 
  ItemKeyGetter = { $args[0].Split(':')[-1] };
};

$value = 'a:b:c:d';


$other = $thing.ItemKeyGetter



& $other $value;


$values = @(
  'a:b',
  'b:c',
  'c:d'
);

$values | % { & $other $value }