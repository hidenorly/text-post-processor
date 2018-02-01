# text-post-processor

replace regexp matched text with specified text (multilines and multi file supported)

```
Usage: targetFile rule.cfg
    -o, --outFile=                   Specify if you want to output as other file
    -v, --verbose                    Enable verbose status output (default:false)
```

```rule.cfg
### comments ###
[[[[a-zA-Z0-9_-]+\.html]]]
!!!</head>!!!
$$$
	<link href='bootstrap.css' rel='stylesheet'>
</head>$$$
///<table.*>///
$$$<table id='result'>$$$
### You can specify match text by !!!matchText!!! ###
### And you can specify replace text by $$$replaceText$$$ ###
### You can use multi lines ###
### You can specify match text as regexp expression if you use ///regexpMatchText/// ###
### EOF ###
```

You can sepecify target file as regexp with ```[[[]]]```
