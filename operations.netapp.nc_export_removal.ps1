Import-Module DataONTAP

<#

.DESCRIPTION
    Removes a client from export rules in our NetApp environment 

.EXAMPLE
    Remove-nc_export_rules -client w17196 -creds my_creds

.PARAMETER client
    The name of the client to remove.

.PARAMETER creds
    Your adm account credentials.  Create a credential object prior by using a command like 'my_creds = Get-Credential'

#>
function remove-nc_export_rules() {
    
    
    Param ( 
            
            # Client to delete
            [string]$client, 
    
            # Credentials to perform delete function.
            [System.Management.Automation.PSCredential]$creds
            
           )

        # Setup Splunk variables
        $scriptname = $PSCommandPath | Split-Path -Leaf
        $scriptname = [System.IO.Path]::GetFileNameWithoutExtension($scriptname)

        $actionReport = New-Object PSObject
        $actionReport | Add-Member deleted_rules @()
                        

        # Setup script variables
        $clusters = @("robsandcl-vip","robcl")
        
        foreach ($cluster in $clusters)
        {

            $logstring = (Connect-NcController -Name $cluster -Credential $creds)
            $RulesToDelete = @()

            # Enumerate the rules that match the specified client.
            Write-Host "Processing cluster " -NoNewline
            Write-Host $cluster -ForegroundColor White -NoNewline
            Write-Host ":"

            # Enumerate and list the client matched rules.
            $enum_rules = Get-NcExportRule
            foreach ($rule in $enum_rules) 
            {

                if ($rule.ClientMatch -eq $client)
                    {
                        
                        $ruletodelete = New-Object PSObject

                        $ruletodelete | Add-Member svm $rule.VserverName
                        $ruletodelete | Add-Member policy $rule.PolicyName
                        $ruletodelete | Add-Member rindex $rule.RuleIndex
                        
                        $RulesToDelete += $ruletodelete

                    }

            }

            # List the rules to delete with a header
            If ( $RulesToDelete.Length -gt 0 )
                {

                    Write-Host "SVM`t`t`t`t`t" -NoNewline
                    Write-Host "Policy`t`t`t`t" -NoNewline
                    Write-Host "Rule Index"

                    Write-Host "---`t`t`t`t`t" -NoNewline
                    Write-Host "------`t`t`t`t" -NoNewline
                    Write-Host "----------"

                    foreach ($ruletodelete in $RulesToDelete)
                        {

                            Write-Host $ruletodelete.SVM "`t`t`t`t" -NoNewline
                            Write-Host $ruletodelete.policy "`t`t`t" -NoNewline
                            Write-Host $ruletodelete.rindex
                            
                        }
                    
                    Write-Host " "
            
                }
                
            # If there are rules to delete, 
            if ( $RulesToDelete.Length -gt 0 )

                {

                    $confirm = Read-Host ("Are you sure you want to delete these export rules for client " + $client + " on cluster " + $cluster + " (Y/N)?")
                    Write-Host " "
                    If ($confirm -eq 'Y' -or $confirm -eq 'y')

                        {   # Rules were deleted

                            foreach ( $ruletodelete in $RulesToDelete )
                                {

                                    Write-Host "Deleting rule for " -NoNewline
                                    Write-Host $client -ForegroundColor Blue -NoNewline
                                    Write-Host " on SVM " -NoNewline
                                    Write-Host $ruletodelete.svm -ForegroundColor Yellow -NoNewline
                                    Write-Host " for policy " -NoNewline
                                    Write-Host $ruletodelete.policy -ForegroundColor Green -NoNewline
                                    Write-Host " and rule index " -NoNewline
                                    Write-Host $ruletodelete.rindex -ForegroundColor White
                                    Remove-NcExportRule -Policy $ruletodelete.policy -Index $ruletodelete.rindex -VserverContext $ruletodelete.svm  -Confirm:$false -ErrorAction SilentlyContinue

                                    $message = "Deleted rule for " + $client + " on SVM " + $ruletodelete.svm + " for policy " + $ruletodelete.policy + " and rule index " + $ruletodelete.rindex + "."
                                    $deleted_rule = New-Object PSObject
                                    $deleted_rule | Add-Member Status $message
                                    $actionReport.deleted_rules += $deleted_rule
                                                

                                }

                            # Write deleted rules to Splunk
                            New-Splunk_Event -severity INFO -message $actionReport -sourceType Powershell -source $scriptname
        

                        }

                else 

                    {   # User cancelled

                        Write-Host "No rules were deleted on cluster: " $cluster "."
                        $message = "User cancelled delete operation."
                        $deleted_rule = New-Object PSObject
                        $deleted_rule | Add-Member Status $message
                        $actionReport.deleted_rules += $deleted_rule
                        New-Splunk_Event -severity INFO -message $actionReport -sourceType Powershell -source $scriptname
                        
                    }

                }

            # No rules to delete on this cluster.
            else 
            
                {

                    Write-Host "No matches for client "$client "on cluster "$cluster "."
                    $message = "No rules to delete for $client on $cluster."
                    $deleted_rule = New-Object PSObject
                    $deleted_rule | Add-Member Status $message
                    $actionReport.deleted_rules += $deleted_rule
                    New-Splunk_Event -severity INFO -message $actionReport -sourceType Powershell -source $scriptname
                
                }

                
            # Disconnect from current controller
            $Global:CurrentNcController = $null

            # Cleaning up loop variables
            $RulestoDelete = @()
            $ruletodelete = $null


        }

        # Cleaning up global variables
        $clusters = $null
    }
    Export-ModuleMember -Function remove-nc_export_rules