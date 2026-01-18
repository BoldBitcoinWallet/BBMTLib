# Performance Evaluation for Large Party TSS Multi-sigs

While our UI currently only does 2-of-2 multi-sig and 2-of-3 for now, you can use our library to do many more.
It does up to 10-20 party keygens over nostr pretty decently.

The only limitation is that the more parties you involve, the more data is transmitted over nostr because each party needs to do a some rounds of computation and send them back to each party.  
A 10 party keygen completes in 45 seconds, and a keysign completes in 35 seconds. Not too shabby.
You just have to be mindful of which nostr relay you are using. If you send too many messages too fast, you will be rate-limited.

Feel free to test the scripts yourself in this branch, just reach out if you have questions.
https://github.com/BoldBitcoinWallet/BBMTLib/tree/Experimental-20-party-script

Test with the following scripts:
- `nostr-keygen-nparty.sh`
- `nostr-keysign-nparty.sh`

## 10 Party Keygen Test

### Statistics

**Total time:** 45 seconds

**Nostr events sent per party:**
- Party 1:  216 nostr events, 2869 KB
- Party 2:  216 nostr events, 2869 KB
- Party 3:  216 nostr events, 2869 KB
- Party 4:  216 nostr events, 2869 KB
- Party 5:  216 nostr events, 2869 KB
- Party 6:  216 nostr events, 2869 KB
- Party 7:  216 nostr events, 2869 KB
- Party 8:  216 nostr events, 2869 KB
- Party 9:  216 nostr events, 2868 KB
- Party 10: 216 nostr events, 2869 KB

**Total nostr events sent:** 2160  
**Total data transmitted:** 28691 KB (29379636 bytes)

## 10 Party Keysign Test

### Statistics

**Total time:** 35 seconds

**Nostr events sent per party:**
- Party 1:  108 nostr events, 183 KB
- Party 2:  108 nostr events, 183 KB
- Party 3:  108 nostr events, 183 KB
- Party 4:  108 nostr events, 183 KB
- Party 5:  108 nostr events, 183 KB
- Party 6:  108 nostr events, 183 KB
- Party 7:  108 nostr events, 183 KB
- Party 8:  108 nostr events, 183 KB
- Party 9:  108 nostr events, 183 KB
- Party 10: 108 nostr events, 183 KB

**Total nostr events sent:** 1080  
**Total data transmitted:** 1834 KB - 1878408 bytes

## 20 Party Keygen Test

### Statistics

**Total time:** 144 seconds

**Nostr events sent per party:**
- Party 1:  456 nostr events, 6072 KB
- Party 2:  456 nostr events, 6072 KB
- Party 3:  456 nostr events, 6072 KB
- Party 4:  456 nostr events, 6072 KB
- Party 5:  456 nostr events, 6072 KB
- Party 6:  456 nostr events, 6072 KB
- Party 7:  456 nostr events, 6072 KB
- Party 8:  456 nostr events, 6072 KB
- Party 9:  456 nostr events, 6072 KB
- Party 10: 456 nostr events, 6072 KB
- Party 11: 456 nostr events, 6072 KB
- Party 12: 456 nostr events, 6072 KB
- Party 13: 456 nostr events, 6072 KB
- Party 14: 456 nostr events, 6072 KB
- Party 15: 456 nostr events, 6072 KB
- Party 16: 456 nostr events, 6072 KB
- Party 17: 456 nostr events, 6072 KB
- Party 18: 456 nostr events, 6072 KB
- Party 19: 456 nostr events, 6072 KB
- Party 20: 456 nostr events, 6072 KB

**Total nostr events sent:** 9120  
**Total data transmitted:** 121454 KB (124369060 bytes)

## 20 Party Keysign Test

### Statistics

**Total time:** 82 seconds

**Nostr events sent per party:**
- Party 1:  228 nostr events, 387 KB
- Party 2:  228 nostr events, 387 KB
- Party 3:  228 nostr events, 387 KB
- Party 4:  228 nostr events, 387 KB
- Party 5:  228 nostr events, 387 KB
- Party 6:  228 nostr events, 387 KB
- Party 7:  228 nostr events, 387 KB
- Party 8:  228 nostr events, 387 KB
- Party 9:  228 nostr events, 387 KB
- Party 10: 228 nostr events, 387 KB
- Party 11: 228 nostr events, 387 KB
- Party 12: 228 nostr events, 387 KB
- Party 13: 228 nostr events, 387 KB
- Party 14: 228 nostr events, 387 KB
- Party 15: 228 nostr events, 387 KB
- Party 16: 228 nostr events, 387 KB
- Party 17: 228 nostr events, 387 KB
- Party 18: 228 nostr events, 387 KB
- Party 19: 228 nostr events, 387 KB
- Party 20: 228 nostr events, 387 KB

**Total nostr events sent:** 4560  
**Total data transmitted:** 7745 KB - 7931104 bytes

## Considerations

I've been trying to find ways to improve this by testing out different MPC TSS libraries like https://github.com/0xCarbon/DKLs23.

But I am hesitant. While the 0xCarbon's DKLs23 library is complete for secpk1, it has not undergone any 3rd party review. At least the current library we use https://github.com/bnb-chain/tss-lib has been in use for 7 years and has completed a security audit in 2019.

Until we find a more proven, production ready TSS library, we will just stick with the current one.
