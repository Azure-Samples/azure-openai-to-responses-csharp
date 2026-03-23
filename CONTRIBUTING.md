# Contributing

This project welcomes contributions and suggestions. Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## How to contribute

1. **Fork** this repository
2. **Create a branch** for your changes (`git checkout -b my-fix`)
3. **Make your changes** — follow existing code style and conventions
4. **Test** your changes:
   ```powershell
   .\migrate.ps1 scan .
   dotnet test tools\Test-Migration\
   ```
5. **Submit a pull request** with a clear description of what you changed and why

## Reporting issues

- Use [GitHub Issues](https://github.com/Azure-Samples/azure-openai-to-responses-csharp/issues) for bug reports and feature requests
- For security vulnerabilities, see [SECURITY.md](SECURITY.md)

## Code style

- **C#**: Follow standard .NET conventions. Use `#pragma warning disable OPENAI001` in Responses API files.
- **PowerShell**: Use approved verbs (`Get-`, `Invoke-`, `Find-`), include `[CmdletBinding()]`, and use `$ErrorActionPreference = "Stop"`.
- **Markdown**: Use ATX headers (`#`), fenced code blocks with language tags, and relative links.
