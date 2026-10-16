/* Steam CEF command-line experiment. Input and all unrelated arguments are
 * preserved verbatim; only known rendering switches are replaced. */
static int cx_cef_token_is(const WCHAR *start, const WCHAR *end, const char *text)
{
    if (end - start >= 2 && *start == '"' && end[-1] == '"') { start++; end--; }
    while (start < end && *text && *start == (unsigned char)*text) { start++; text++; }
    return start == end && !*text;
}
static int cx_cef_replace_token(const WCHAR *start, const WCHAR *end)
{
    static const char *tokens[] = {"--disable-gpu", "--disable-gpu-compositing",
        "--use-angle=swiftshader-webgl", "--use-angle=swiftshader", "--use-angle=d3d11",
        "--use-angle=gl", "--use-gl=angle", "--disable-direct-composition", "--ignore-gpu-blocklist", "--in-process-gpu"};
    unsigned int i;
    for (i = 0; i < sizeof(tokens) / sizeof(tokens[0]); i++)
        if (cx_cef_token_is(start, end, tokens[i])) return 1;
    return 0;
}
static void cx_cef_gpu_command(const WCHAR *source, WCHAR *destination, int opengl)
{
    static const char d3d_flags[] = " --in-process-gpu --use-gl=angle --use-angle=d3d11 --disable-direct-composition --ignore-gpu-blocklist";
    static const char gl_flags[] = " --in-process-gpu --use-gl=angle --use-angle=gl --disable-direct-composition --ignore-gpu-blocklist";
    const WCHAR *start, *scan;
    WCHAR *out = destination;
    unsigned int slashes;
    int quoted;
    const char *flag;
    while (*source)
    {
        while (*source == ' ' || *source == '\t') *out++ = *source++;
        start = source; quoted = 0; slashes = 0;
        while (*source && (quoted || (*source != ' ' && *source != '\t')))
        {
            if (*source == '"' && !(slashes & 1)) quoted = !quoted;
            slashes = *source == '\\' ? slashes + 1 : 0;
            source++;
        }
        if (!cx_cef_replace_token(start, source))
            for (scan = start; scan < source; scan++) *out++ = *scan;
    }
    for (flag = opengl ? gl_flags : d3d_flags; *flag; flag++) *out++ = (unsigned char)*flag;
    *out = 0;
}
