import type_checker.retention.discovery.discovery_request_status;

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    finish_discovery_requests();
}
