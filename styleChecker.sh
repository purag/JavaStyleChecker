#!/bin/bash
#styleChecker: A tool to help check style in programs, according to Ord's specs
#Made by Anish Kannan
#Thanks to Nick Crow (Nack) for regex help
#TODO Check mix of tabs and spaces. Indentation. Suggests that are
#directly copypastable

OPTIND=1         # Reset in case getopts has been used previously in the shell.

totalLinesOver80=0
totalMagicNums=0
totalBadVarNames=0
verbose=0
showSteps=0
totalNumLines=0
totalNumComments=0
totalMissingFileHeaders=0
totalMissingMethodHeaders=0
totalMissingClassHeaders=0

show_help()
{
    echo "Usage: [OPTION] FILE..."
    echo "Checks style for FILE(s). Ord-style"
    echo "-v, --verbose     print the results of each grep to find which lines have issues."
    echo "-s, --show        show all of the steps along the way."
}

while getopts "h?v" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    v)  verbose=1
        ;;
    s)  showSteps=1
        ;;
    esac
done

shift $((OPTIND-1))

if (($# < 1)); then
    show_help
    exit 0
fi

#Loop through files.
for fileName in "$@"
do
    localLinesOver80=0
    localMagicNums=0
    localBadVarNames=0
    localNumLines=0
    localNumComments=0
    localMissingFileHeaders=0
    localMissingMethodHeaders=0
    localMissingClassHeaders=0
    echo "Checking $fileName"
 
    #####################COMMENT PROPORTIONS###############
    if (($showSteps == 1)); then
        echo "Checking for comment proportions."
    fi

    #Handle // comments
    localNumLines=$(wc -l < $fileName)
    localNumComments=$(grep -E -c "\/\/" $fileName)
    
    #For later to keep track of which lines are comments
    doubleSlashCommentLines=$(grep -n "\/\/" $fileName | cut -f1 -d ":")
    
    #Initializing it for each file.
    unset commentArray
    unset doubleSlashCommentArray
    read -a doubleSlashCommentArray <<< $doubleSlashCommentLines

    #Looping through line nums to put into the array.
    DSArraySize=$((${#doubleSlashCommentArray[@]} - 1)) 
    for commentArrayIndex in `seq 0 $DSArraySize`
    do
        #To check whether a line is a comment, just check the value at line number.
        #A double slash comment is 1
        commentArray[${doubleSlashCommentArray[$commentArrayIndex]}]=1
    done


    #Handle /* */ comments
    startCommentLines=$(grep -n "\/\*" $fileName | cut -f1 -d ":")
    endCommentLines=$(grep -n "\*\/" $fileName | cut -f1 -d ":")

    #Initializing for each file.
    unset startCommentArray
    unset endCommentArray

    #Putting these in an array.
    read -a startCommentArray <<< $startCommentLines
    read -a endCommentArray <<< $endCommentLines

    arraySize=$((${#startCommentArray[@]} - 1)) 
   
    #Actually checking the lengths of multiline comments.
    index=0
    for index in `seq 0 $arraySize`
    do
        localNumComments=$((${endCommentArray[$index]} - ${startCommentArray[$index]} + $localNumComments))
    
        #For later, to keep track of which lines are comments. A "/* */" comment
        #is 2.
        for commentArrayIndex in `seq ${startCommentArray[$index]} ${endCommentArray[$index]}`
        do
            commentArray[$commentArrayIndex]=2
        done
    done
        
    proportion=$(bc <<< "scale=2; $localNumComments / $localNumLines * 100")
    
    echo "** $proportion% of $fileName is comments. 25%-50% is usually good."
    echo
    totalNumLines=$(($localNumLines + $totalNumLines))
    totalNumComments=$(($localNumComments + $totalNumComments))
      
    ##########################LONG LINES###################
    if (($showSteps == 1)); then
        echo "Checking for lines over 80 chars..."
    fi

    if (($verbose == 1)); then
        grep -EnH '.{81}' $fileName
    fi

    localLinesOver80=$(grep -Ec '.{81}' "$fileName")
    totalLinesOver80=$(($localLinesOver80 + $totalLinesOver80))
    if (($localLinesOver80 != 0)); then
        echo " ** $localLinesOver80 lines over 80 chars in $fileName"
        echo
    fi
    #######################BAD VARIABLE NAMES##############
    #Catches when the variable is assigned. 
    #Catches single letter vars with numbers, ex. i1
    #Updated: 5/28/15 21:11 (Purag Moumdjian)
    if (($showSteps == 1)); then
        echo "Checking for 1 letter variable names."
    fi

    if (($verbose == 1)); then
        grep -PinH "([a-z]+(\s?\[\])*\s)([a-z]([0-9]*)\s?(?=[;:=]))" $fileName 
    fi
    localBadVarNames=$(grep -Pci "([a-z]+(\s?\[\])*\s)([a-z]([0-9]*)\s?(?=[;:=]))" $fileName)
    totalBadVarNames=$(($localBadVarNames + $totalBadVarNames))
    if (($localBadVarNames != 0)); then
        echo "** $localBadVarNames single-letter names in $fileName"
        echo
    fi

    ############FILE HEADERS################
    #Unintelligent, looking for the word "login" lines after "/*"
    #Case-insensitive.
    #Thank you stack overflow
    if (($showSteps == 1)); then
        echo "Checking for missing file headers..."
    fi

    localMissingFileHeaders=$(grep -Pzic "(?s)(\/\*|\/\/).*\n.*login" $fileName)
    if (($localMissingFileHeaders == 0)); then
        echo "** Missing File Header in $fileName"
        echo
        totalMissingFileHeaders=$((1+$totalMissingFileHeaders))
    fi

    ############METHOD/CLASS HEADERS################
    #First looks for access modifiers then checks for names of classes.
    #Case-insensitive.
    
    #First get the lines with an access modifier: These are classes,
    #instance variables, and methods.
    linesWithAccessModifier=$(grep -Eon "public|private" $fileName | cut -f1 -d ":")

    #Initializing for each file.
    unset accessModifierLinesArray
    read -a accessModifierLinesArray <<< $linesWithAccessModifier

    lastLineIndexToCheck=$((${#accessModifierLinesArray[@]} - 1))

    #Initializing for each file
    methodIndex=0
    classIndex=0
    instanceVarIndex=0
    #Arrays.
    unset methodNames
    unset classNames
    unset instanceVarLines

    #Get all the names we will search for. Looking for open parens
    for lineNumIndex in `seq 0 $lastLineIndexToCheck`
    do
        #First removing instance var objects with same line declaration and initialization.
        instanceVarCheck=$(sed "${accessModifierLinesArray[$lineNumIndex]}!d" $fileName | grep -Eo "=")
        #If there is an "=", this must be an instance variable.
        if [[ ! -z "$instanceVarCheck" ]]; then
            instanceVarLines[$instanceVarIndex]=${accessModifierLinesArray[$lineNumIndex]}
            instanceVarIndex=$(($instanceVarIndex + 1))

        else
           
            #Check for method names
            result=$(sed "${accessModifierLinesArray[$lineNumIndex]}!d" $fileName | grep -Po "\S+(?=\()")

            #If the word is a valid method then put it in methodNames
            if [[ ! -z "$result" ]]; then
                methodNames[$methodIndex]=$result
                methodIndex=$(($methodIndex + 1))

            #If the word is not a method then check if it is a class
            else
                result=$(sed "${accessModifierLinesArray[$lineNumIndex]}!d" $fileName | grep -Po "class\s+[^{\s]+" | cut -f2 -d " ")

                #If the word is a valid class then put it in classNames
                if [[ ! -z "$result" ]]; then
                    classNames[$classIndex]=$result
                    classIndex=$(($classIndex + 1))

                #Must be an instance variable. Store the line number to check for magic vars.
                else
                    instanceVarLines[$instanceVarIndex]=${accessModifierLinesArray[$lineNumIndex]}
                    instanceVarIndex=$(($instanceVarIndex + 1))

                fi
            fi
        fi
    done
    
    if (($showSteps == 1)); then
        echo "Checking for missing method headers..."
    fi
    lastMethodIndexToCheck=$((${#methodNames[@]} - 1))
    
    #Grep the names of methods to see if there is an appropriate comment.
    for methodName in `seq 0 $lastMethodIndexToCheck`
    do
        result=$(grep -Eic "Name:\s*${methodNames[$methodName]}" $fileName)

        if ((result == 0)); then
            echo "** Missing method header for ${methodNames[$methodName]} in $fileName"
            totalMissingMethodHeaders=$((1+$totalMissingMethodHeaders))
        fi
    done
 
    lastClassIndexToCheck=$((${#classNames[@]} - 1))
    
    if (($showSteps == 1)); then
        echo "Checking for missing class headers..."
    fi

    #Grep the names of classes to see if there is an appropriate comment.
    for className in `seq 0 $lastClassIndexToCheck`
    do
        result=$(grep -Eic "Name:\s*${classNames[$className]}" $fileName)

        if (($result == 0)); then
            echo "** Missing class Header for ${classNames[$className]} in $fileName"
            totalMissingClassHeaders=$((1+$totalMissingClassHeaders))
        fi
    done
    #################MAGIC NUMBERS#########################
    if (($showSteps == 1)); then
        echo "Checking for magic numbers..."
    fi
    
    #initializing it for each file.
    unset magicNumsArray

    magicNumLines=$(grep -Pon '[\s,\+\-\/\*=](([2-9]\d*)|(1\d+))' $fileName | cut -f1 -d ":")
    
    read -a magicNumsArray <<< $magicNumLines

    lastNumIndexToCheck=$((${#magicNumsArray[@]} - 1))
    lastInstanceVarIndex=$((${#instanceVarLines[@]} - 1))

    #From these magic numbers, remove those that are actually instance variables.
    numLine=0
    while [ $numLine -lt $lastNumIndexToCheck ]
    do

        #First check if the magic number appeared in a "//" comment.
        isBad=1
        if [[ ${commentArray[${magicNumsArray[$numLine]}]} -eq 1 ]]; then
            #We know there is a comment on the line, want to check if it starts before the number.
            #Eg: "int potato = 0 //64 is my favorite number" should be ok.
            checkCommentInLine=$(sed "${commentArray[${magicNumsArray[$numLine]}]}!d" $fileName | awk -F "//" '{print $1}')

            #Need to remove extraneous matches that are due to commented out portions.
            numsToBeIgnored=$(sed "${commentArray[${magicNumsArray[$numLine]}]}!d" $fileName | awk -F "//" '{print $2}')
            
            #Note there is a space here before numsToBeIgnored in case the magic num is right after the "//".
            commentIgnoreResult=$( echo " $numsToBeIgnored" | grep -Po '[\s,\+\-\/\*=]([2-9]\d*)|(1\d+)' | wc -l)

            #If there are commented magic numbers, then increment numLine to skip those.
            if [[ -z $commentResult ]]; then
                numLine=$(($numLine+ $commentIgnoreResult))

                #We've already removed magic nums after the comment. Any other
                #matches are actual magic numbers.
                commentArray[${magicNumsArray[$numLine]}]=3
            fi

            #Still need to check if this number is magic.
            commentResult=$( echo " $checkCommentInLine" | grep -Pon '[\s,\+\-\/\*=]([2-9]\d*)|(1\d+)' | cut -f1 -d ":")

            #If the grep didn't find the number, then it was after the "//"
            if [[ -z $commentResult ]]; then
                isBad=0 
            fi

        #If the magic number appeared in a "/* */" comment.
        else
            if [[ ${commentArray[${magicNumsArray[$numLine]}]} -eq 2 ]]; then
                isBad=0
            fi
        fi
                
        #If it is still bad, then check it's an instance variable.
        #If so then it isn't a magic number. Note: ignoring static and final.
        #public instance variables are also ok.
        if [[ $isBad -eq 1 ]]; then
            for numInstanceVar in `seq 0 $lastInstanceVarIndex`
            do
                if [[ ${magicNumsArray[$numLine]} -eq ${instanceVarLines[$numInstanceVar]} ]]; then
                    isBad=0
                fi
            done
        fi
        
        if (($isBad == 1)); then
            localMagicNums=$(($localMagicNums + 1))

            if (($verbose == 1)); then
                echo -n "Line ${magicNumsArray[$numLine]}:"
                sed "${magicNumsArray[$numLine]}!d" $fileName
            fi
        fi

        #Increment for loop.
        numLine=$(($numLine + 1))
    done
    
    totalMagicNums=$(($localMagicNums + $totalMagicNums))
    
    if [[ !$localMagicNums -eq 0 ]]; then
        echo "** $localMagicNums magic nums in $fileName"
        echo
    fi
done

proportion=$(bc <<< "scale=2; $totalNumComments / $totalNumLines * 100")

echo "-----RESULTS-----"
echo "$proportion% of files are comments. 25%-50% is usually good."
echo "$totalMissingMethodHeaders missing method headers."
echo "$totalMissingClassHeaders missing class headers."
echo "$totalMissingFileHeaders missing file headers."
echo "$totalBadVarNames bad variable names."
echo "$totalLinesOver80 lines over 80."
echo "$totalMagicNums magic numbers."

