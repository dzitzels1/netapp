<#

Note: This function finds and lists storage array-based snapshots associated with Hyper-V and VMware volumes on the NetApp storage array.
Note: External functions are commented out and the script will work without them however, the code for those functions is not included.

#>
Import-Module DataONTAP

<#

.DESCRIPTION
    Enumerates but does not remove Hyper-V and ESX snapshots at or older than a specified number of days.

.EXAMPLE
    find-nc_esx_hyp_old_snapshots -creds $my_creds [-days <days>] [-server <API_server_to_use>]

.PARAMETER creds
    Your administrator account credentials.  Create a credential object prior by using a command like '$my_creds = Get-Credential'

.PARAMETER days
    Number of days to search for snapshots.  Snapshots will be flagged if they are equal to or older than this many days.  5 is the default.

.PARAMETER server
    API server to use for enumerating clusters.  'netapp-api-server-1' and 'netapp-api-server-2' is the default server set with netapp-api-server-1 being the default server.

#>
function find-nc_esx_hyp_old_snapshots()

{

    Param ( 
            
            # Credentials to perform find function.
            [Parameter(Mandatory=$true,HelpMessage="Create a credentials object using the Get-Credential command.")]
            [System.Management.Automation.PSCredential]$creds,

            # Number of days to search against
            [Parameter(Mandatory=$false,HelpMessage="Snapshots will be logged if they are equal to or older than this many days")]
            [int]$expire_days = 5,

            # systemName
            [Parameter(Mandatory=$false,HelpMessage="API Server")]
            [ValidateSet('netapp-api-server-1','netapp-api-server-2')]
            [string]$APIServer = "netapp-api-server-1"


           )

if ( -not ( [System.Management.Automation.PSTypeName]'ServerCertificateValidationCallback' ).Type )
{
$certCallback = @"
    using System;
    using System.Net;
    using System.Net.Security;
    using System.Security.Cryptography.X509Certificates;
    public class ServerCertificateValidationCallback
    {
        public static void Ignore()
        {
            if(ServicePointManager.ServerCertificateValidationCallback ==null)
            {
                ServicePointManager.ServerCertificateValidationCallback +=
                    delegate
                    (
                        Object obj,
                        X509Certificate certificate,
                        X509Chain chain,
                        SslPolicyErrors errors
                    )
                    {
                        return true;
                    };
            }
        }
    }
"@

Add-Type $certCallback

}

[ServerCertificateValidationCallback]::Ignore()
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


            # Setup Splunk variables
            $scriptname = $PSCommandPath | Split-Path -Leaf
            $scriptname = [System.IO.Path]::GetFileNameWithoutExtension($scriptname)
            $SplunkReport = New-Object PSObject
            $SplunkReport | Add-Member logged_lines @()


            # Set up credentials
            $username = $creds.GetNetworkCredential().Username
            $storage_username = 'domain\' + $creds.GetNetworkCredential().Username
            $password = $creds.GetNetworkCredential().Password
            [System.Security.SecureString]$strong_password = ConvertTo-SecureString -String $password -AsPlainText -Force
            $API_creds = New-Object System.Management.Automation.PSCredential ($username,$strong_password)
            $Storage_creds = New-Object System.Management.Automation.PSCredential ($storage_username,$strong_password)

            # Set up e-mail function
            $mail_from = "user@somedomain.com"
            $mail_to = "other_user@somedomain.com"
            $mail_subject = "Snapshots of ESX and Hyper-V volumes over "
            $mail_subject += $expire_days.ToString()
            $mail_subject += " days old"
            $mail_smtp_server = "smtp-relay.domain.com"
            $mail_message = $null

            # Enumerate clusters from API server
            $URI = "https://$($APIServer)/api/6.0/ontap/clusters/"
            $response = Invoke-RestMethod -Method Get -Credential $API_creds -Uri $URI -ContentType "application/json"

            $clusters = @()
            for ( $i = 0; $i -lt $response.result.records.Length; $i++ )
                {

                    $discovered_cluster = New-Object PSObject
                    $cluster_name = $response.result.records[$i].name + '-vip'
                    $discovered_cluster | Add-Member Name $cluster_name
                    $clusters += $discovered_cluster

                }
            $cluster_name = $null


            # Set up expiration date
            $today = Get-Date
            $snap_table = New-Object PSObject
            $snap_table | Add-Member snaps @()

            # Process each cluster
            foreach ($cluster in $clusters)
            {

                try 
                    {
            
                        $conn = $null
                        $conn = Connect-NcController -Name $cluster.Name -Credential $Storage_creds -ErrorAction Stop
                
                    } # End try
                    
                catch 
                    {

                        if ( !($cluster.name.Contains("mysecurecluster")) )
                            {

                                $message = "Could not connect to cluster: "
                                $message += $cluster.Name
                                $message += ".  Verify that the cluster is accessible and check your credentials."
                                Write-Host $message
                                $SplunkReport.logged_lines += $message
                
                            } # End if

                    } # End catch
            
                if ( !( $null -eq $conn ) )
                    {

                        # Get the $SVMs
                        $svms = Get-NcVserver -Controller $conn

                        # Check SVMs for Hyper-V or ESX SVMs
                        foreach ( $svm in $svms )
                            {

                                
                               if ( ( $svm.VserverName.Contains('HYPERV') ) -or ( $svm.VserverName.Contains('hyperv') ) -or ( $svm.VserverName.Contains('ESX') ) -or ( $svm.VserverName.Contains('esx') )  )
                                    {

                                        # Get Hyper-V and ESX SVM volumes
                                        $vols = Get-NcVol -Vserver $svm.VserverName -Controller $conn | Where-Object { $_.VolumeStateAttributes.IsVserverRoot -eq $false }

                                        # Process each Hyper-V volume
                                        foreach ( $vol in $vols )
                                            {

                                                # Get all of the volume snapshots and process them.
                                                $snaps = Get-NcSnapshot -Volume $vol.name -Controller $conn
                                                
                                                foreach ( $snap in $snaps )
                                                    {

                                                        $age = ($today - $snap.AccessTimeDT)
                                                        # Check to see if the snapshot meets or is older than the expiration date.
                                                        if ( $age.Days -ge $expire_days )
                                                            {

                                                                $snapshot = New-Object PSObject
                                                                $snapshot | Add-member Age $age.Days
                                                                $snapshot | Add-member Cluster $conn.Name
                                                                $snapshot | Add-member Volume $vol.Name
                                                                $snapshot | Add-member SVM $svm.VserverName
                                                                $snapshot | Add-member Snapshot $snap.Name
                                                                $snap_table.snaps += $snapshot
                                                                $SplunkReport.logged_lines += $snapshot

                                                            } # End if ( $age.Days -ge $expire_days )

                                                    } # End foreach ( $snap in $snaps )

                                            } # End foreach ( $vol in $vols )

                                    } # End if ( ( $svm.name.Contains('HYP') ) -or ( $svm.name.Contains('hyp') ) -or ( $svm.name.Contains('ESX') ) -or ( $svm.name.Contains('esx') )  )

                            } # foreach ( $svm in $svms )

                    } # End if ( !( $null -eq $conn ) )
                
                } # End foreach ($cluster in $clusters)

    $entries = $snap_table.snaps
    
    if ( !($entries.Length -eq 0) )
        {

            Write-Host ($entries |Format-Table -AutoSize |Out-String)
            $mail_message = ($entries |Format-Table -AutoSize |Out-String)
            Send-MailMessage -From $mail_from -To $mail_to -Subject $mail_subject -Body -$mail_message -SmtpServer $mail_smtp_server
#            New-SNIncident -requestedby 'SNUser' -requestedfor 'SNUser' -assignmentGroup 'MY-SN-ASSIGNMENT-GROUP' -shortDescription $mail_Subject -Description $mail_message -username '<some_username>' -password '<some_password>'
        }

    if ( !($SplunkReport.logged_lines.Length -eq 0) )
        {        

#           New-Splunk_Event -severity INFO -message $SplunkReport -sourceType Powershell -source $scriptname

        }


} # End function find-nc_esx_hyp_old_snapshots()

# Export-ModuleMember -Function find-nc_esx_hyp_old_snapshots
