# azure-functions-sisimai

The [Sisimai](http://libsisimai.org/) running on the [Azure Functions](https://azure.microsoft.com/services/functions/)

[![Deploy to Azure](https://azuredeploy.net/deploybutton.png)](https://azuredeploy.net/)

## SYNOPSIS

1. Check the https endpoint url for function, and copy it.

2. Check the path of your mailbox file. Maildir is not supported.

3. Send a POST request to endpoint url with curl as followings.

```
ENDPOINT_URL="https://yourfuncname.azurewebsites.net/api/sisimai?code=..."
curl -X POST \
     -H "Content-Type: text/plain" \
     --data-binary @path/to/mailbox \
     $ENDPOINT_URL
```

## SEE ALSO

* [Sisimai](http://libsisimai.org/)
* [sisimai/p5-Sisimai](https://github.com/sisimai/p5-Sisimai)
