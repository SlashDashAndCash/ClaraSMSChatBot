
# Change Log
All notable changes to this project will be documented in this file.


## [Unreleased] - YYYY-mm-dd

### Added

### Changed
- Reduced boiler plate in hilink class
- Reboot LTE modem on fatal error
- Wait 4 * recipients + 4 sec. after sending SMS
- Exception handling on token request
- Increased message size to 160 chars

### Fixed
- send-sms uri
- delete-sms body
- immediate logging to stdout, stderr


## [v0.2.0] - 2024-10-21

### Added
- Error handling and retry on HiLink request failure
- Environment Variables for container configuration
- Reboot LTE modem with command line argument

### Changed
- Delete SMS immediately after processing

### Fixed
- Typos in README

## [v0.1.0] - 2024-10-20

Initial release

