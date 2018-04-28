using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class Replace : MonoBehaviour {

public Shader replace;
	// Use this for initialization
	void Start () {
		GetComponent<Camera>().SetReplacementShader(replace,"");
	}
	
	// Update is called once per frame
	void Update () {
		
	}
}
