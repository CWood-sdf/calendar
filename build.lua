vim.fn.jobstart("bash ./build.sh", {
    on_exit = function(code)
        vim.notify(code)
    end,
    on_stdout = function(data)
        vim.notify(vim.inspect(data))
    end,
    on_stderr = function(data)
        vim.notify(vim.inspect(data))
    end
})

