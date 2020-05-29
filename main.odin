package main

import "core:fmt"

import "lex"

main :: proc()
{
     tokens := lex.lex_file("test.c");
     for token in tokens
         {
         fmt.printf("%v\n", token);
     }
}
