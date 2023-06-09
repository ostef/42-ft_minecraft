#module_parameters () (Enable_Asserts := true);

#scope_module

Fmt :: #import "Fmt";

#scope_export

FormatString :: Fmt.format;
FormatToCString :: Fmt.format_to_cstring;
Print :: Fmt.print;
Println :: Fmt.println;

#load "memory.jai";
#load "array.jai";
#load "string.jai";
#load "logging.jai";

#if Basic.MEMORY_DEBUGGER
{
    Common_Allocation_Leaves :: Basic.Procedure_To_Elide.[
        .{"AllocNonNull", "Common"},
        .{"Alloc", "Common"},
        .{"AllocArray", "Common"},
        .{"Realloc", "Common"},
        .{"StringClone", "Common"},
        .{"StringCloneToCString", "Common"},
        .{"StringJoin", "Common"},
        .{"FormatString", "Common"},
        .{"FormatToCString", "Common"},
        .{"ArrayReserve", "Array"},
        .{"HashMapInit", "Hash_Map"},
        .{"HashMapGrow", "Hash_Map"},
    ];
}

Assert :: (assertion : bool, fmt_str := "", args : ..Any, location := #caller_location) #expand
{
    #if Enable_Asserts
    {
        if !assertion
        {
            if context.handling_assertion_failure
                return;

            context.handling_assertion_failure = true;
            message := FormatString (fmt_str, ..args);
            context.assertion_failed (location, message);
            context.handling_assertion_failure = false;
        }
    }
}

Panic :: (fmt_str := "", args : ..Any, location := #caller_location) #expand
{
    if context.handling_assertion_failure
        return;

    context.handling_assertion_failure = true;
    message := FormatString (fmt_str, ..args);
    context.assertion_failed (location, message);
    context.handling_assertion_failure = false;
}

Initialize :: inline (item : *$T)
{
    initializer :: initializer_of (T);
    #if initializer
        initializer (item);
    else
        memset (item, 0, size_of (T));
}

Initialize :: inline (item : *$T, count : s64)
{
    initializer :: initializer_of (T);
    #if initializer
    {
        for i : 0..count - 1
            initializer (item + i);
    }
    else
    {
        memset (item, 0, size_of (T) * count);
    }
}

OffsetOf :: ($T : Type, $member : string, $location := #caller_location) -> s64 #expand
{
    Compiler :: #import "Compiler";

    #insert -> string
    {
        info := cast (*Type_Info_Struct) type_info (T);
        if info.type != .STRUCT
            Compiler.compiler_report (FormatString ("Type % is not a struct", T), loc = location);

        result := -1;
        for info.members
        {
            if it.name == member
            {
                result = it.offset_in_bytes;
                break;
            }
        }

        if result < 0
            Compiler.compiler_report (FormatString ("Struct % does not have a member named %", T, member), loc = location);

        return FormatString ("return %;", result);
    }
}

DefaultValue :: ($T : Type) -> T #expand
{
    val : T;

    return val;
}

#scope_file

IsNumeric :: inline (type : Type) -> bool
{
    info := cast (*Type_Info) type;

    return info.type == .INTEGER || info.type == .FLOAT;
}

#scope_export

Min :: (a : $T, b : T) -> T #must #expand
#modify { return IsNumeric (T); }
{
    return ifx a < b then a else b;
}

Max :: (a : $T, b : T) -> T #must #expand
#modify { return IsNumeric (T); }
{
    return ifx a > b then a else b;
}

MinMax :: (a : $T, b : T) -> min : T, max : T #must #expand
#modify { return IsNumeric (T); }
{
    if a < b
        return a, b;
    else
        return b, a;
}

Clamp :: (x : $T, min : T, max : T) -> T #must #expand
#modify { return IsNumeric (T); }
{
    return Min (Max (x, min), max);
}

Saturate :: (x : $T) -> T #must #expand
#modify { return IsNumeric (T); }
{
    return Clamp (x, 0, 1);
}

Abs :: (x : $T) -> T #must #expand
#modify { return IsNumeric (T); }
{
    return ifx x < 0 then -x else x;
}

Sign :: (x : $T) -> T #must #expand
#modify { return IsNumeric (T); }
{
    return cast (T) ifx x < 0 then -1 else ifx x > 0 then 1 else 0;
}

Lerp :: (a : float, b : float, t : float) -> float #must #expand
{
    return a * (1 - t) + b * t;
}

InverseLerp :: (a : float, b : float, t : float) -> float #must #expand
{
    return (t - a) / (b - a);
}
