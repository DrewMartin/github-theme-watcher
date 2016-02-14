# Github Theme Watcher

This watches a github repo containing a shopify theme and when changes to the theme are pushed to master it uploads those changes to the configured theme on your store. This allows multiple people to collaborate on a theme and have version control without having to copy and paste changes in. Multiple themes repos can be watched by the app. This is designed to run in Heroku.

### Setup:
1. Clone this repo and create a Heroku app with it (https://devcenter.heroku.com/articles/git#creating-a-heroku-remote)
2. Create a [private app](https://docs.shopify.com/api/authentication/creating-a-private-app) in Shopify
3. Inside the repository settings in Github create a webhook. The payload url will be the herokuapp you just set up, with the path `push`. E.g. `https://github-theme-watcher.herokuapp.com/push`. Optionally set up a secret token.
4. Create an [access token](https://help.github.com/articles/creating-an-access-token-for-command-line-use/) in Github (only needed if the repository is private) 
5. Set up config vars

### Heroku config
See [Heroku docs](https://devcenter.heroku.com/articles/config-vars#setting-up-config-vars-for-a-deployed-application) on how to actually set the config variables.

Because the app can work with multiple themes, all config vars must be prefixed with the github org and repo like this `<org name>__<repo name>__<var name>`, with characters other than a-z, 0-9 and underscores being converted to underscores. For example if this repository contained a theme and you wanted to reference the theme_id the var you'd add to Heroku is `DrewMartin__github_theme_watcher__theme_id`.

##### Config vars
| Variable | Description |
|---|---|
| theme_id (**required**) | The id of the theme that this will push to in shopify. |
| shopify_domain (**required**) | The full myshopify.com domain of your store. Eg `themetest.myshopfiy.com` |
| shopify_api_key (**required**) | The private app api key created inside Shopify |
| shopify_password (**required**) | The private app password created inside Shopify |
| github_secret_token | Then token created when creating the Github webhook. |
| git_auth_token | The access token created inside Github. Only required for private repos |

