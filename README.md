# Nudelo
Nudelo is a very primitive command-line HTML minifier written in [D programming language](https://dlang.org/).

## Usage examples
In order to use nudelo from the command-line, you simply pass a source and destination file name:
```
nudelo -i foo.html -o foo.min.html
```
Another way is to send data to the stdin and redirect the stdout to a file:
```
nudelo <foo.html >foo.min.html
```
Also, you can specify the command-line utilities to minify the fragments of JavaScript and CSS contained in the HTML:
```
nudelo -i foo.html -o foo.min.html --js uglifyjs --css cssnano
```
