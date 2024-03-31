vim.schedule(function()
    vim.fn.jobstart("cd lua/ccronexpr && gcc ccronexpr.c -I. -Wall -Wextra -std=c89 -o libccronexpr.so -fPIC -shared", {
        on_exit = function(code)
            print(code)
        end,
    })
end)

