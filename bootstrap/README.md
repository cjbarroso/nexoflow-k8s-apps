Use kubectl apply to deploy soft-serve
Create a public/private keypair
Use it on the secret
Load the public part into soft-serve with 

ssh -p 23231 localhost user create argocd
ssh -p 23231 localhost user add-pubkey argocd $(cat public-key)



Create a repo for the apps and push it to soft-serve

argocd cert add-ssh --batch --from ~/.ssh/known_hosts

Create app-of-apps app deploy, point to the created repo
kubectl apply it
