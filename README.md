# VMware Cross Cluster DRS with PowerCLI

This repo has code wich does the following:

1. Periodically checks source cluster datastores and compute resource utilization.
2. If storage/compute resource is high then it moves VMs across to a different cluster.
3. Emails administrators about the high resource utilization in the source cluster.

Note: To run the script replace the variable placeholders with actual values. 
