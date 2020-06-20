# YY-Reunion
Quick links: [itch.io](https://yellowafterlife.itch.io/gamemaker-yy-reunion) (pre-built binaries)

Hello! This tool does a few things:

* Imports resources and resource tree folders into the project that are still in the directory but not referenced in the project / not added into any resource tree folder (e.g. due to mishaps during version control merges)
* Removes references to resources that no longer exist in project directory (removes warnings on project load).
* Removes references to missing resources from resource tree folder files.  
    Newly relocated resources are placed inside a "reunion" folder in their respective resource tree section.

Don't forget to make a backup of your project just in case!
