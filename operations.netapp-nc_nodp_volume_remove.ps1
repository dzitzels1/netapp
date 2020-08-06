Import-Module DataONTAP

<#

.DESCRIPTION
    Decommissions but does not completely remove a set of volumes in our NetApp environment 

.EXAMPLE
    remove-nc_nodp-volume -volume volume1[,volume2][...] -cluster cluster1 -creds $my_creds

.PARAMETER volumes
    An array of target volumes to decommission.

.PARAMETER cluster
    The name of the cluster where the target volumes resides.

.PARAMETER creds
    Your adm account credentials.  Create a credential object prior by using a command like '$my_creds = Get-Credential'

#>

function remove-nc_nodp_volume() {

    Param ( 
            
            # Target volume to decommission
            [string[]]$volumes,
    
            # Cluster where target volume resides
            [string]$cluster,

            # Credentials to perform delete function.
            [System.Management.Automation.PSCredential]$creds
            
           )

    # Set up Splunk logging variables
    $scriptname = $PSCommandPath | Split-Path -Leaf
    $scriptname = [System.IO.Path]::GetFileNameWithoutExtension($scriptname)
    $splunkLog = New-Object PSObject
    $splunkLog | Add-Member logged_messages @()

    # Other useful variables
    $date = Get-Date (Get-Date).AddMonths(1) -f yyyyMMdd
    $delete_confirmed = $false
    $root_volume = $false
    $disposed_volume = $false
    
    # Connect to cluster.
    try {
        
        Connect-NcController -Name $cluster -Credential $creds -ErrorAction Stop | Out-Null
    
    }
    catch {
        
        Write-Host "Could not connect to cluster $cluster.  Verify that the cluster is accessible and check your credentials."
        break
    
    }
    
    # Create a volume list
    $list_volumes = @()
    for ( $i=0; $i -lt $volumes.Length; $i++ )
        {

            $vol = Get-NcVol -Name $volumes[$i]
            if ( $null -eq $vol) 
                { 
                    
                    Write-Host "Volume" $volumes[$i] "was not found on the array."
                    continue 
                
                }
            $new_name = 'Dispose_' + $date + '_' + $vol.Name
            $volume_to_delete = New-Object PSObject
            $volume_to_delete | Add-Member Name $vol.Name
            $volume_to_delete | Add-Member NewName $new_name
            $volume_to_delete | Add-Member SVM $vol.Vserver
            $volume_to_delete | Add-Member Aggr $vol.Aggregate
            $list_volumes += $volume_to_delete

        } 

    $message = "The following volumes will be decommissioned: "
    Write-Host $message
    for ( $i=0; $i -lt $list_volumes.Length; $i++ )
        {

            $message = $list_volumes[$i].Name
            Write-Host $message

        }
    $message = "Are you sure (Y/N)?: "
    $answer = Read-Host -Prompt $message
    if ( ($answer -eq "Y") -or ($answer = 'y') ) { $delete_confirmed = $true }
    

    if ( $delete_confirmed )

        {

            # Check to see if we are trying to decomm a root volume
            for ( $i=0; $i -lt $list_volumes.Length; $i++ )
                {

                    # If the name contains the word root, we will assume root volume.
                    $temp_name = $list_volumes[$i].Name
                    if ( ( $temp_name -like '*root*' ) -or ( $temp_name -like '*ROOT*' ) )
                        {
                            
                            $root_volume = $true
                            $message = $temp_name + " is a root volume.  Cannot dispose of a root volume."
                            Write-Host $message
                            $splunkLog.logged_messages += $message
                                    
                        }

                    # If the volume aggregate contains the word root, we will assume root volume.
                    if ( ( $list_volumes[$i].Aggr -like '*root*' ) -or ( $list_volumes[$i].Aggr -like '*ROOT*' ) )
                        {
                            
                            $root_volume = $true
                            $message = $temp_name + " is a root volume.  Cannot dispose of a root volume."
                            Write-Host $message
                            $splunkLog.logged_messages += $message
                                    
                        }

                    # If the volume name is vol0, we will assume root volume.
                    if ( $list_volumes[$i].Name -eq 'vol0' )
                        {
                            
                            $root_volume = $true
                            $message = $temp_name + " is a root volume.  Cannot dispose of a root volume."
                            Write-Host $message
                            $splunkLog.logged_messages += $message
                                    
                        }

                    
                }                        


            # Check to see if we are trying to decomm a disposed volume
            for ( $i=0; $i -lt $list_volumes.Length; $i++ )
                {

                    $temp_name = $list_volumes[$i].Name
                    if ( $temp_name -like '*Dispose*' )
                        {
                            
                            $disposed_volume = $true
                            $message = $temp_name + " is a disposed volume.  Cannot dispose of a disposed volume."
                            Write-Host $message
                            $splunkLog.logged_messages += $message
                                    
                        }
                    
                }                        

            If ( !($root_volume) -and !($disposed_volume) )
                {
                                        
                    for ( $i=0; $i -lt $list_volumes.Length; $i++ )
                    {
                
                        # Rename the volume.
                        Rename-NcVol -Name $list_volumes[$i].Name -NewName $list_volumes[$i].NewName -VserverContext $list_volumes[$i].SVM | Out-Null
                        
                        # Dismount the volume.
                        Dismount-NcVol -Name $list_volumes[$i].NewName -VserverContext $list_volumes[$i].SVM | Out-Null

                        # Set the volume as Restricted.
                        Set-NcVol -Name $list_volumes[$i].NewName -Restricted -VserverContext $list_volumes[$i].SVM | Out-Null

                        $message = 'Volume ' + $list_volumes[$i].Name + ' has been decommissioned.'
                        Write-Host $message
                        $splunkLog.logged_messages += $message

                    }

                }
                            
        }
                        
    else

        {

            $message = "User cancelled volume decommission."
            Write-Host $message
            $splunkLog.logged_messages += $message

        }



    New-Splunk_Event -severity INFO -message $splunkLog -sourceType Powershell -source $scriptname

}


Export-ModuleMember -Function remove-nc_nodp_volume

