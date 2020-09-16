# Note: This script logs to my Splunk environment but that function is not included in the upload so I have commented out the line that actually logs.

<#

In my environment, we have a 'cooling off' period of 30 days between decommissioning and completely deleting a volume.  This script covers the decommission task.

To be considered decommissioned, a volume must go through the following:

1. Renamed by pre-pending a dispose and date stamp string so that the volume is named as such: 'Dispose_yyyyMMdd_volume1'.
2. Dismounted so that it cannot be accessed.
3. Set as Restricted so that it cannot be mounted.

This script does not take into account any data protection mechanisms (SnapMirror, SnapVault, etc) that may be attached to the volume.  That may come in a later version.

#>

Import-Module DataONTAP

<#

.DESCRIPTION
    Decommissions but does not completely remove a set of volumes in a NetApp environment 

.EXAMPLE
    remove-nc_nodp-volume -volume volume1[,volume2][,...] -cluster cluster1 -creds $my_creds

.PARAMETER volumes
    An array of target volumes to decommission.

.PARAMETER cluster
    The name of the cluster where the target volumes resides.

.PARAMETER creds
    Your administrator account credentials.  Create a credential object prior by using a command like '$my_creds = Get-Credential'

#>

function Remove-NcNoDP_Volume() {

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
    $SplunkReport = New-Object PSObject
    $SplunkReport | Add-Member logged_messages @()

    # Set up credentials
    $storage_username = 'DOMAIN\' + $creds.GetNetworkCredential().Username
    $password = $creds.GetNetworkCredential().Password
    [System.Security.SecureString]$strong_password = ConvertTo-SecureString -String $password -AsPlainText -Force
    $Storage_creds = New-Object System.Management.Automation.PSCredential ($storage_username,$strong_password)



    # Other useful variables
    $date = Get-Date (Get-Date).AddMonths(1) -f yyyyMMdd
    $decommission_confirmed = $false
    
    # Connect to cluster.
    try 
        {

            $conn = $null
            $conn = Connect-NcController -Name $cluster.Name -Credential $Storage_creds -ErrorAction Stop

        } # End try
    
    catch 
        {

            if ( !( $cluster.name.Contains("secure-cluster") ) )
                {

                    $message = "Could not connect to cluster: "
                    $message += $cluster.Name
                    $message += ".  Verify that the cluster is accessible and check your credentials."
                    Write-Host $message
                    $SplunkReport.logged_lines += $message
                    break

                } # End if

        } # End catch

    # Create a volume list to delete
    $list_volumes = @()
    for ( $i=0; $i -lt $volumes.Length; $i++ )
        {

            $vol = $null
            $vol = Get-NcVol -Name $volumes[$i] -Controller $conn

            if ( $null -eq $vol) # Volume does not exist.
                { 
                    
                    Write-Host "Volume" $volumes[$i] "was not found on the array."
                    continue 

                }

            elseif ( $vol.VolumeStateAttributes.IsVserverRoot -eq $true )  # Volume is a root volume.
                {
                
                    $message = "Cannot decommission a root volume: "
                    $message += $vol.Name
                    Write-Host $message
                    continue

                }
                
            elseif ( $vol.Name -like '*Dispose*' ) # Volume is already decommissioned.
                {
                    
                    $message = $temp_name + " is a disposed volume.  Cannot dispose of a disposed volume."
                    Write-Host $message
                    $SplunkReport.logged_messages += $message
                    continue
                            
                }
        

            else
                {

                    $new_name = 'Dispose_' + $date + '_' + $vol.Name
                    $volume_to_delete = New-Object PSObject
                    $volume_to_delete | Add-Member Name $vol.Name
                    $volume_to_delete | Add-Member NewName $new_name
                    $volume_to_delete | Add-Member SVM $vol.Vserver
                    $list_volumes += $volume_to_delete
            
                }
                        
        } 

    # Display the volumes and ask for confirmation.
    $message = "The following volumes will be decommissioned: "
    Write-Host $message
    Write-Host ($list_volumes |Format-Table -AutoSize |Out-String)

    $message = "Are you sure (Y/N)?: "
    $answer = Read-Host -Prompt $message
    if ( ($answer -eq "Y") -or ($answer = 'y') ) { $decommission_confirmed = $true }
    

    if ( $decommission_confirmed )

        {

            for ( $i=0; $i -lt $list_volumes.Length; $i++ )
            {
        
                # Rename the volume.
                Rename-NcVol -Name $list_volumes[$i].Name -NewName $list_volumes[$i].NewName -VserverContext $list_volumes[$i].SVM | Out-Null
                
                # Dismount the volume.
                Dismount-NcVol -Name $list_volumes[$i].NewName -VserverContext $list_volumes[$i].SVM | Out-Null

                # Set the volume as Restricted.
                Set-NcVol -Name $list_volumes[$i].NewName -Restricted -VserverContext $list_volumes[$i].SVM | Out-Null

                $message = 'Volume ' 
                $message += $list_volumes[$i].Name 
                $message += ' has been decommissioned.'
                Write-Host $message
                $SplunkReport.logged_messages += $message

            }

                            
        }
                        
    else

        {

            $message = "User cancelled volume decommission."
            Write-Host $message
            $SplunkReport.logged_messages += $message

        }



#    New-Splunk_Event -severity INFO -message $SplunkReport -sourceType Powershell -source $scriptname

}


Export-ModuleMember -Function Remove-NcNoDP_Volume

