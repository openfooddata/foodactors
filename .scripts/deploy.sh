#!/bin/bash
set -e # Exit with nonzero exit code if anything fails

SOURCE_BRANCH="master"
TARGET_BRANCH="gh-pages"

function doCheck {
    mkdir .out
    java -jar .scripts/ofd-actors-converter.jar ./data/
}

function doGenerate {
    java -jar .scripts/ofd-actors-converter.jar ./data/
}

# Pull requests and commits to other branches shouldn't try to deploy, just build to verify
if [ "$TRAVIS_PULL_REQUEST" != "false" -o "$TRAVIS_BRANCH" != "$SOURCE_BRANCH" ]; then
    echo "Skipping deploy; just doing check."
    doCheck
    exit 0
fi


# Save some useful information
REPO=`git config remote.origin.url`
SSH_REPO=${REPO/https:\/\/github.com\//git@github.com:}
SHA=`git rev-parse --verify HEAD`
#git reflog -1 | sed 's/^.*: //'
MSG=`git log -1 --oneline`

# Clone the existing gh-pages for this repo into .out/
# Create a new empty branch if gh-pages doesn't exist yet (should only happen on first deply)
git clone $REPO .out
cd .out
git checkout $TARGET_BRANCH || git checkout --orphan $TARGET_BRANCH
cd ..

# Clean out existing contents
echo "Clean out existing contents..."
rm -fr .out/* || exit 0

# Run generate script
echo "Generate content ..."
doGenerate
echo "Copy static content ..."
cp -r static/* .out/
# config the cloned repo
cd .out
git config user.name "Travis CI"
git config user.email "$COMMIT_AUTHOR_EMAIL"

# If there are no changes to the compiled out (e.g. this is a README update) then just bail.
if [ -z `git diff --exit-code` ]; then
    echo "No changes to the output on this push; exiting."
    exit 0
fi

# Commit the "changes", i.e. the new version.
# The delta will show diffs between new and old versions.
git add . --all
git commit -m "Deploy to GitHub Pages: ${MSG}"

# Get the deploy key by using Travis's stored variables to decrypt deploy_key.enc
ENCRYPTED_KEY_VAR="encrypted_${ENCRYPTION_LABEL}_key"
ENCRYPTED_IV_VAR="encrypted_${ENCRYPTION_LABEL}_iv"
ENCRYPTED_KEY=${!ENCRYPTED_KEY_VAR}
ENCRYPTED_IV=${!ENCRYPTED_IV_VAR}
openssl aes-256-cbc -K $ENCRYPTED_KEY -iv $ENCRYPTED_IV -in ../foodactors_rsa.enc -out ../id_rsa -d
chmod 600 ../id_rsa
eval `ssh-agent -s`
ssh-add ../id_rsa

# Now that we're all set up, we can push.
git push $SSH_REPO $TARGET_BRANCH
