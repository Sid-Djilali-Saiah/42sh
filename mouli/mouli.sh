#! /bin/sh

blue="\033[34m"
red="\033[31m"
green="\033[32m"
orange="\033[33m"
base="\033[00m"

test_nb=0
crash=0
passed=0

verbose=0
memcheck=0

rm -rf __tmp

for index
do
        if [ $index = "--verbose" ]
        then
                verbose=1
        elif [ $index = "--verbose=full" ]
        then
                verbose=2
        elif [ $index = "--memcheck" ]
        then
                memcheck=1
        elif [ $index = "--help" ]
        then
                echo "Usage: $0 [--verbose[=full]] [--memcheck]\n"
                echo "Description:\n\t--verbose\tDisplay the tests."
                echo "\t--verbose=full\tDisplay your/tcsh's output."
                echo "\t--memcheck\tCheck velgrind's error and count crashs."
                echo $orange"\nWarning: Some features can't be tested"
                echo "\t- env, setenv and unsetenv with correct input"
                echo "\t- << redirection" $base
                exit
        fi
done

test() {
        test_nb=$((test_nb+1))
        echo "=== Test $test_nb - $1 ==="

        if [ $verbose = 1 ] || [ $verbose = 2 ]
        then
                echo $orange"Test {\n$2\n}" $base
        fi

        if [ $memcheck = 1 ]
        then
                echo $2 | valgrind --log-file=valgrind.log ./mysh > mysh.log 2>&1
                mysh_ret=$?

                cat valgrind.log | grep "SIGSEGV" > grep

                if [ -s grep ]
                then
                        echo $red "KO: Crashed !" $base
                        crash=$((crash+1))
                        echo
                        return 1
                fi
        else
                echo $2 | ./mysh > mysh.log 2>&1
                mysh_ret=$?
        fi

        echo $2 | tcsh > tcsh.log 2>&1
        tcsh_ret=$?

        diff mysh.log tcsh.log > diff
        if [ ! -s diff ]
        then
                if [ $mysh_ret = $tcsh_ret ]
                then
                        if [ $memcheck = 1 ]
                        then
                                cat valgrind.log | grep -i "invalid" > grep
                                cat valgrind.log | grep -i "uninitialised" >> grep

                                if [ -s grep ]
                                then
                                        echo $orange "KO: memory errors were detected" $base
                                        return 1
                                else
                                        echo $green "OK: Passed" $base
                                        passed=$((passed+1))
                                        return 0
                                fi

                        else
                                echo $green "OK: Passed" $base
                                passed=$((passed+1))
                                return 0
                        fi
                else
                        echo $red "KO: Bad return value"
                        echo "  Expected $tcsh_ret, but got $mysh_ret" $base
                        failed=$((failed+1))
                        return 1
                fi
        else
                echo $red "KO: Output differs" $base
                if [ $verbose = 2 ]
                then
                        echo $red"=== TCSH output ===" $base
                        cat tcsh.log
                        echo $red"=== Your output ===" $base
                        cat mysh.log
                fi
                return 1
        fi

        echo
}

echo "=== Test 00 -- Compilation ==="
make fclean > /dev/null
make re > /dev/null
if [ $? != 0 ] || [ ! -f mysh ]
then
        echo $red "KO: Compilation failed" $base
        exit
else
        echo $green "OK: Passed" $base
fi

if [ $memcheck = 0 ]
then
        echo $orange"\nWarning: memcheck disabled, crashes won't be detected" $base
        echo $orange"Rerun with --memcheck to track memory errors and count crashes" $base
fi

mkdir __tmp
cp $0 __tmp/
cp mysh __tmp/
cd __tmp/

#TESTS BEGIN

echo $blue "\n======= Tests minishell 1 =======\n" $base

test "Empty" ""
test "Empty 2" "             "
test "Empty 3" "        \t   \t     "
test "Simple exec" "echo bonjour"
test "Simple exec 2" "ls /"
test "Simple exec 3" "echo plusieurs arguments"
test "Simple wrong command" "sel"

export OLDPATH=$PATH
export PATH="$PATH:./"
test "Path test" "mysh"
export PATH=$OLDPATH

test "Setenv (bad input)" "setenv 42ok salut"
test "Setenv (bad input) 2" "setenv ok- salut"
test "Setenv (bad input) 3" "setenv ok-"
test "Unsetenv (bad input)" "unsetenv"
test "Unsetenv (bad input) 2" "unsetenv PATH lol"

test "Builtin cd" "cd\nls"
test "Builtin cd 2" "cd\ncd -\nls"
test "Builtin cd (invalid case)" "cd $0"
test "Builtin cd (invalid case) 2" "cd jaimelesel"

test "Error handling (bin not compatible)" "./Makefile"
mkdir __tmp
test "Error handling (exec a directory)" "./__tmp"
rmdir __tmp
echo "int main() {char *s = 0; s[0] = 0;}" > test.c
gcc test.c -o segv
test "Error handling (segfault)" "./segv"
echo "int main() {int a = 0; int s = 3 / a;}" > test.c 2>&1
gcc test.c -o segv
test "Error handling (div by zero)" "./segv"
rm segv test.c

echo $blue "\n======= Tests minishell 2 =======\n" $base

test "Separator" "ls / ; ls /"
test "Separator 2" "ls / ; ls / ; ls / ; echo bonjour le sel"
test "Separator 3" "ls / ;;;;;;;;;;;;;;"

test "Pipe" "ls / | cat"
test "Pipe 2" "echo salut |cat|wc -l"
test "Pipe (builtin)" "env | grep PWD"
test "Pipe (builtin)" "setenv | grep PWD"
test "Pipe (builtin)" "cd trololol | cat -e"
test "Pipe (invalid case)" "echo bonjour |"
test "Pipe (invalid case) 2" "||| echo bonjour |||||"
test "Pipe (invalid case) 3" "echo | bonjour"
test "Pipe (invalid case) 4" "echo | bonjour |"

test "Redirection <" "cat < $0"
test "Redirection > (won't work if separator isn't fonctionnal)" "echo salut > lol ; cat log"
test "Redirection > (won't work if separator isn't fonctionnal) (builtin)" "> file env ; cat file | grep PWD"
test "Redirection > (won't work if separator isn't fonctionnal)" "echo //TEST >> /usr/include/stdlib.h"
test "Redirection >> (won't work if separator isn't fonctionnal)" "echo salut > lol ; echo salut >> lol ; cat lol"

test "Error handling" "|"
test "Error handling" "<|"
test "Error handling" "echo > |"
test "Error handling" ">> echo >>"
test "Error handling" "| cat >> echo << >> << |"

test "Ambiguous redirects" "ls | cat < ok"
test "Ambiguous redirects" "ls > ok | cat"
test "Ambiguous redirects" "ls > ok | cat < lol"

# test "Big pipe (this one gonna be a bit long)" "man gcc | cat -e|cat -e| cat    -e" & sleep 10s ; kill $! > /dev/null 2>&1
# if [ $? = 0 ]
# then
#         echo $red "KO: Timed out after 10s\n" $base
# else
#         passed=$((passed+1))
# fi
# test_nb=$((test_nb+1))

test "Exoctic redirection <" "< $0 cat"
test "Exoctic redirection >" "> salut echo bonjour; cat bonjour"
test "Exoctic redirection >>" ">> salut echo bonjour; >> salut echo bonjour   ; cat bonjour"
test "Exoctic redirections" "cat < $0 -e > test; < test cat"
test "Exoctic redirections" "< > lol ok cat"

test "Advanced test" "ls / | cat > ok ; cat ok"
test "Advanced test" "ls / | cat | cat -e | cat > ok ; cat ok"
test "Advanced test" "cat < $0 | cat -e"
test "Advanced test" "cat < $0 | cat -e > salut ; cat salut -e"
test "Advanced test" "< /bin ls > a; cat a"
test "Advanced test" "ls << /bin | cat -e > /dev/null < ls"
test "Advanced test" "ls > file < 42; cat file"
test "Advanced test" "echo bonjour < salut test > yo        ;    cat yo"
test "Advanced test" "echo | cat | cat | cat | wc"
test "Advanced test" "echo >> salut >> salut"
test "Advanced test" "echo bonjour > salut; echo bonjour >> salut; cat -e < salut | cat"
test "Advanced test" "echo > salut | wc"
test "Advanced test" "echo < salut | wc"
test "Advanced test" "echo < salut |"
test "Advanced test" "cat < cat < cat cat"
test "Advanced test" "echo > salut ; < salut cat | grep salut | > test wc -l; cat test"

if [ $passed = $test_nb ]
then
        echo $orange"\n=== Starting random tests ===\n" $base

        echo "#! /usr/bin/python\nimport random" > gen.py
        echo "command = ['echo', 'bonjour', '|', 'cat', '-e', 'ls', '|', 'wc', '>>', 'cat', 'salut', 'env', 'setenv', 'unsetenv', '<', '>>', '>', '|']" >> gen.py
        echo "length = random.randint(0, len(command) - 1)\nfor i in range(length):\n\tprint command[random.randint(0, len(command) - 1)]," >> gen.py

        i=0
        for i in $(seq 1 1000)
        do
                command=$(python gen.py)
                echo "Test $i -- <$command> : \c"
                test "" "command" > /dev/null

                if [ $? != 0 ]
                then
                        i=100
                        echo $red"KO !" $base
                else
                        echo $green"OK: Passed" $base
                fi
                i=$((i+1))
        done
fi

echo "\n=== Test $((test_nb+1)) - Last test (you gonna segfault) ==="
echo "ls" | env -i ./mysh
if [ $? = 0 ] || [ $? = 1 ] || [ $? = 84 ]
then
        echo $green "GG" $base
else
        echo $red "KO: Oops!" $base
fi

#TESTS END

echo "\n===== Results ======"
echo $green "Passed: $(($passed*100/($test_nb)))%" $base
echo $red "Crashed: $(($crash*100/($test_nb)))%" $base

cd ..
rm -rf __tmp
