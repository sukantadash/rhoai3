## Get token
Notice how we are using /maas-api/v1/api-keys

``` bash
TOKEN_RESPONSE=$(curl -sSk \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"name": "test1", "description": "Test key for test1", "expiration": "10m"}' \
  "${HOST}/maas-api/v1/api-keys") && \
TOKEN=$(echo $TOKEN_RESPONSE | jq -r .token) && \
JTIID=$(echo $TOKEN_RESPONSE | jq -r .jti) && \
echo "Token response: ${TOKEN_RESPONSE} \n" && \
echo "-------------- \n" && \
echo "Token obtained: ${TOKEN:0:20}..." && \
echo "JTI: ${JTIID}"

```

Check if the API token is still valid using the JTI id that we got from the previous curl command.

```bash
curl -sSk -H "Authorization: Bearer $(oc whoami -t)" -w "\n%{http_code}" "${HOST}/maas-api/v1/api-keys/${JTIID}"
```