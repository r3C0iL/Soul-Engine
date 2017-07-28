#pragma once
#include "GPGPU\GPUBuffer.h"

#include "Metrics.h"
#include "GPGPU\OpenCL\OpenCLDevice.h"

/* Buffer for open cl. */
template<class T>
class OpenCLBuffer :public GPUBuffer<T> {

public:

	/*
	 *    Constructor.
	 *    @param [in,out]	parameter1	If non-null, the first parameter.
	 *    @param 		 	parameter2	The second parameter.
	 */

	OpenCLBuffer(OpenCLDevice*, uint){}
	/* Destructor. */
	~OpenCLBuffer(){}

protected:

private:

};