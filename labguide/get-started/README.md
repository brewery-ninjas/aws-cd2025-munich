# 1. Get started with your Lab

## Access the lab environment

Access the website address provided by the event organizer. The URL includes an access-code parameter. If you only received the access-code from the event organizer, click [here](https://catalog.us-east-1.prod.workshops.aws/) to access the site. Click the Get Started button and proceed to the next step.

![](//docs/images/Event_Engine_GetStarted.png)

Click the Email One-Time Password (OTP) button.

![](//docs/images/Event_Engine_OTP.png)

Enter your available email address and click the Send passcode button.

![](//docs/images/Event_Engine_New_Email.png)

Check your email inbox for an email with the subject Your one-time passcode and copy the passcode. Paste the copied passcode as shown below, then click the Sign in button.

![](//docs/images/Event_Engine_New_Passcode.png)

If you accessed the Workshop Studio using the link in step 1 without an access-code, you will see a screen to enter the Event access code. Enter the access-code provided by the event organizer and click the Next button.

The screen will change to the Review and Join screen for the Workshop Studio event terms. After carefully reading the user terms, check I agree and click the Join Event button.

You have now transitioned to the workshop screen. The menu in the upper left contains the workshop content, and you can access the AWS Console window by clicking the link in AWS account access at the bottom left. You can also check the Access Key and Secret Access Key for the CLI environment.

![](//docs/images/Event_Engine_Detail.png)

## Cloud9

The workshop is primarily conducted in AWS Cloud9 . AWS Cloud9 provides an environment where you can store project files and develop and run various container applications. This IDE supports multiple programming languages and includes a powerful code editing feature set, including a runtime debugger and an integrated terminal. It provides a comprehensive set of tools for coding, building, running, testing, and debugging, and supports the process of deploying software to the cloud.

The Cloud9 setup requires a few more configurations for this lab.

Go to Cloud9 by following [this link](https://console.aws.amazon.com/cloud9control). Then click on Open.

![](//docs/images/AWS_Cloud9.png)

Click on the green + icon and choose "Open Preferences". Then choose "AWS Settings" in the left navigation bar and disable the "AWS managed temporary credentials" option:
![](//docs/images/cloud9-temp.png)

## Pre-Script to setup lab

In order to save time, the basic setup of the EKS cluster and storage resources is automated. You just need to run the script by copying the command below into the terminal at the bottom of your Cloud9 window

```bash
curl -sL https://raw.githubusercontent.com/brewery-ninjas/aws-cd2025-munich/refs/heads/main/workshop-environment/prep_environment.sh | bash
```

The setup will take 15-20 minutes so join us on a brief journey of the theory behind the next steps in your lab.

Once the setup script is completed and we finished the overview, you can continue to chapter [2. Explore your lab setup](/labguide/explore)
