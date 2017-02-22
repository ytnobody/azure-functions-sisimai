# azure-functions-sisimai

The [Sisimai](http://libsisimai.org/) running on the [Azure Functions](https://azure.microsoft.com/services/functions/)

[![Deploy to Azure](https://azuredeploy.net/deploybutton.png)](https://azuredeploy.net/)

![image](https://bytebucket.org/ytnobody/images/raw/7ebf0d7130da17fe3d98bcefe5ffd0c6ec8554db/blogimg/sisimai-on-azure-functions.gif)

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
