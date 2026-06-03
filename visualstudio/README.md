# Visual Studio VSIX

This folder builds a Visual Studio Marketplace package for the Enhanced Aspire Starter template.

The NuGet `dotnet new` package remains the primary template source. The VSIX build script converts the synchronized template source into a Visual Studio multi-project `.vstemplate` package and wraps it in a VSIX.

## Build

Requires Visual Studio with the Visual Studio extension development workload.

```powershell
.\visualstudio\Build-Vsix.ps1
```

Output:

```text
artifacts\vsix\EnhancedAspireStarter.VisualStudio.0.1.3.vsix
```

Double-click the VSIX to install it locally. Restart Visual Studio, then search for `Enhanced Aspire Starter` in the New Project dialog.

## Publish

Marketplace publishing requires a Visual Studio Marketplace publisher and a personal access token.

```powershell
$env:VS_MARKETPLACE_PAT = "<token>"
.\visualstudio\Publish-Marketplace.ps1
```

The publish script finds `VsixPublisher.exe` through Visual Studio SDK installation metadata. Keep the PAT out of source control and terminal logs.

## Maintenance

After changing the source starter app:

```powershell
.\scripts\Sync-TemplateSource.ps1
dotnet pack
.\visualstudio\Build-Vsix.ps1
```
