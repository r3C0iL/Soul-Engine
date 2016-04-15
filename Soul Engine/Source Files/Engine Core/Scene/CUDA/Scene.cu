#include "Scene.cuh"

#define RAY_BIAS_DISTANCE 0.0002f 
#define BVH_STACK_SIZE 32

Scene::Scene()
{
	objectsSize = 0;
	allocatedObjects = 0;
	allocatedSize = 0;

	compiledSize = 0;
	newFaceAmount = 0;
	cudaMallocManaged(&objectList,
		allocatedObjects*sizeof(Object*));

	objectsToRemove.clear();

	//give the addresses for the data
	bvh = new BVH(&faceIds, &mortonCodes);
}


Scene::~Scene()
{

	cudaFree( objectBitSetup); // hold a true for the first indice of each object
	cudaFree(objIds); //points to the object
	cudaFree(faceIds);
	cudaFree(mortonCodes);

	//Variables concerning object storage

	cudaFree(objectList);
	cudaFree(objectRemoval);
}


struct is_scheduled
{
	__host__ __device__
		bool operator()(const Object* x)
	{
		return (x->requestRemoval);
	}
};



// Template structure to pass to kernel
template <typename T>
struct KernelArray : public Managed
{
public:
	T*  _array;
	int _size;

public:
	__device__ int Size() const{
		return _size;
	}

	__device__ T operator[](const int& i)const {
		return _array[i];
	}
	__device__ T& operator[](const int& i) {
		return _array[i];
	}
	__device__ T& operator[](const uint& i) {
		return _array[i];
	}
	__device__ T operator[](const uint& i)const {
		return _array[i];
	}
	__host__ KernelArray() {
		_array = NULL;
		_size = 0;

	}

	// constructor allows for implicit conversion

	__host__ KernelArray(thrust::device_vector<T>& dVec) {
		_array = thrust::raw_pointer_cast(&dVec[0]);
		_size = (int)dVec.size();
	}
	__host__ KernelArray(T* arr, int size) {
		_array = arr;
		_size = size;
	}
	__host__ ~KernelArray(){

	}

};



//morton codes

__device__ const uint morton256_x[256] =
{
	0x00000000,
	0x00000001, 0x00000008, 0x00000009, 0x00000040, 0x00000041, 0x00000048, 0x00000049, 0x00000200,
	0x00000201, 0x00000208, 0x00000209, 0x00000240, 0x00000241, 0x00000248, 0x00000249, 0x00001000,
	0x00001001, 0x00001008, 0x00001009, 0x00001040, 0x00001041, 0x00001048, 0x00001049, 0x00001200,
	0x00001201, 0x00001208, 0x00001209, 0x00001240, 0x00001241, 0x00001248, 0x00001249, 0x00008000,
	0x00008001, 0x00008008, 0x00008009, 0x00008040, 0x00008041, 0x00008048, 0x00008049, 0x00008200,
	0x00008201, 0x00008208, 0x00008209, 0x00008240, 0x00008241, 0x00008248, 0x00008249, 0x00009000,
	0x00009001, 0x00009008, 0x00009009, 0x00009040, 0x00009041, 0x00009048, 0x00009049, 0x00009200,
	0x00009201, 0x00009208, 0x00009209, 0x00009240, 0x00009241, 0x00009248, 0x00009249, 0x00040000,
	0x00040001, 0x00040008, 0x00040009, 0x00040040, 0x00040041, 0x00040048, 0x00040049, 0x00040200,
	0x00040201, 0x00040208, 0x00040209, 0x00040240, 0x00040241, 0x00040248, 0x00040249, 0x00041000,
	0x00041001, 0x00041008, 0x00041009, 0x00041040, 0x00041041, 0x00041048, 0x00041049, 0x00041200,
	0x00041201, 0x00041208, 0x00041209, 0x00041240, 0x00041241, 0x00041248, 0x00041249, 0x00048000,
	0x00048001, 0x00048008, 0x00048009, 0x00048040, 0x00048041, 0x00048048, 0x00048049, 0x00048200,
	0x00048201, 0x00048208, 0x00048209, 0x00048240, 0x00048241, 0x00048248, 0x00048249, 0x00049000,
	0x00049001, 0x00049008, 0x00049009, 0x00049040, 0x00049041, 0x00049048, 0x00049049, 0x00049200,
	0x00049201, 0x00049208, 0x00049209, 0x00049240, 0x00049241, 0x00049248, 0x00049249, 0x00200000,
	0x00200001, 0x00200008, 0x00200009, 0x00200040, 0x00200041, 0x00200048, 0x00200049, 0x00200200,
	0x00200201, 0x00200208, 0x00200209, 0x00200240, 0x00200241, 0x00200248, 0x00200249, 0x00201000,
	0x00201001, 0x00201008, 0x00201009, 0x00201040, 0x00201041, 0x00201048, 0x00201049, 0x00201200,
	0x00201201, 0x00201208, 0x00201209, 0x00201240, 0x00201241, 0x00201248, 0x00201249, 0x00208000,
	0x00208001, 0x00208008, 0x00208009, 0x00208040, 0x00208041, 0x00208048, 0x00208049, 0x00208200,
	0x00208201, 0x00208208, 0x00208209, 0x00208240, 0x00208241, 0x00208248, 0x00208249, 0x00209000,
	0x00209001, 0x00209008, 0x00209009, 0x00209040, 0x00209041, 0x00209048, 0x00209049, 0x00209200,
	0x00209201, 0x00209208, 0x00209209, 0x00209240, 0x00209241, 0x00209248, 0x00209249, 0x00240000,
	0x00240001, 0x00240008, 0x00240009, 0x00240040, 0x00240041, 0x00240048, 0x00240049, 0x00240200,
	0x00240201, 0x00240208, 0x00240209, 0x00240240, 0x00240241, 0x00240248, 0x00240249, 0x00241000,
	0x00241001, 0x00241008, 0x00241009, 0x00241040, 0x00241041, 0x00241048, 0x00241049, 0x00241200,
	0x00241201, 0x00241208, 0x00241209, 0x00241240, 0x00241241, 0x00241248, 0x00241249, 0x00248000,
	0x00248001, 0x00248008, 0x00248009, 0x00248040, 0x00248041, 0x00248048, 0x00248049, 0x00248200,
	0x00248201, 0x00248208, 0x00248209, 0x00248240, 0x00248241, 0x00248248, 0x00248249, 0x00249000,
	0x00249001, 0x00249008, 0x00249009, 0x00249040, 0x00249041, 0x00249048, 0x00249049, 0x00249200,
	0x00249201, 0x00249208, 0x00249209, 0x00249240, 0x00249241, 0x00249248, 0x00249249
};

// pre-shifted table for Y coordinates (1 bit to the left)
__device__ const uint morton256_y[256] = {
	0x00000000,
	0x00000002, 0x00000010, 0x00000012, 0x00000080, 0x00000082, 0x00000090, 0x00000092, 0x00000400,
	0x00000402, 0x00000410, 0x00000412, 0x00000480, 0x00000482, 0x00000490, 0x00000492, 0x00002000,
	0x00002002, 0x00002010, 0x00002012, 0x00002080, 0x00002082, 0x00002090, 0x00002092, 0x00002400,
	0x00002402, 0x00002410, 0x00002412, 0x00002480, 0x00002482, 0x00002490, 0x00002492, 0x00010000,
	0x00010002, 0x00010010, 0x00010012, 0x00010080, 0x00010082, 0x00010090, 0x00010092, 0x00010400,
	0x00010402, 0x00010410, 0x00010412, 0x00010480, 0x00010482, 0x00010490, 0x00010492, 0x00012000,
	0x00012002, 0x00012010, 0x00012012, 0x00012080, 0x00012082, 0x00012090, 0x00012092, 0x00012400,
	0x00012402, 0x00012410, 0x00012412, 0x00012480, 0x00012482, 0x00012490, 0x00012492, 0x00080000,
	0x00080002, 0x00080010, 0x00080012, 0x00080080, 0x00080082, 0x00080090, 0x00080092, 0x00080400,
	0x00080402, 0x00080410, 0x00080412, 0x00080480, 0x00080482, 0x00080490, 0x00080492, 0x00082000,
	0x00082002, 0x00082010, 0x00082012, 0x00082080, 0x00082082, 0x00082090, 0x00082092, 0x00082400,
	0x00082402, 0x00082410, 0x00082412, 0x00082480, 0x00082482, 0x00082490, 0x00082492, 0x00090000,
	0x00090002, 0x00090010, 0x00090012, 0x00090080, 0x00090082, 0x00090090, 0x00090092, 0x00090400,
	0x00090402, 0x00090410, 0x00090412, 0x00090480, 0x00090482, 0x00090490, 0x00090492, 0x00092000,
	0x00092002, 0x00092010, 0x00092012, 0x00092080, 0x00092082, 0x00092090, 0x00092092, 0x00092400,
	0x00092402, 0x00092410, 0x00092412, 0x00092480, 0x00092482, 0x00092490, 0x00092492, 0x00400000,
	0x00400002, 0x00400010, 0x00400012, 0x00400080, 0x00400082, 0x00400090, 0x00400092, 0x00400400,
	0x00400402, 0x00400410, 0x00400412, 0x00400480, 0x00400482, 0x00400490, 0x00400492, 0x00402000,
	0x00402002, 0x00402010, 0x00402012, 0x00402080, 0x00402082, 0x00402090, 0x00402092, 0x00402400,
	0x00402402, 0x00402410, 0x00402412, 0x00402480, 0x00402482, 0x00402490, 0x00402492, 0x00410000,
	0x00410002, 0x00410010, 0x00410012, 0x00410080, 0x00410082, 0x00410090, 0x00410092, 0x00410400,
	0x00410402, 0x00410410, 0x00410412, 0x00410480, 0x00410482, 0x00410490, 0x00410492, 0x00412000,
	0x00412002, 0x00412010, 0x00412012, 0x00412080, 0x00412082, 0x00412090, 0x00412092, 0x00412400,
	0x00412402, 0x00412410, 0x00412412, 0x00412480, 0x00412482, 0x00412490, 0x00412492, 0x00480000,
	0x00480002, 0x00480010, 0x00480012, 0x00480080, 0x00480082, 0x00480090, 0x00480092, 0x00480400,
	0x00480402, 0x00480410, 0x00480412, 0x00480480, 0x00480482, 0x00480490, 0x00480492, 0x00482000,
	0x00482002, 0x00482010, 0x00482012, 0x00482080, 0x00482082, 0x00482090, 0x00482092, 0x00482400,
	0x00482402, 0x00482410, 0x00482412, 0x00482480, 0x00482482, 0x00482490, 0x00482492, 0x00490000,
	0x00490002, 0x00490010, 0x00490012, 0x00490080, 0x00490082, 0x00490090, 0x00490092, 0x00490400,
	0x00490402, 0x00490410, 0x00490412, 0x00490480, 0x00490482, 0x00490490, 0x00490492, 0x00492000,
	0x00492002, 0x00492010, 0x00492012, 0x00492080, 0x00492082, 0x00492090, 0x00492092, 0x00492400,
	0x00492402, 0x00492410, 0x00492412, 0x00492480, 0x00492482, 0x00492490, 0x00492492
};

// Pre-shifted table for z (2 bits to the left)
__device__ const uint morton256_z[256] = {
	0x00000000,
	0x00000004, 0x00000020, 0x00000024, 0x00000100, 0x00000104, 0x00000120, 0x00000124, 0x00000800,
	0x00000804, 0x00000820, 0x00000824, 0x00000900, 0x00000904, 0x00000920, 0x00000924, 0x00004000,
	0x00004004, 0x00004020, 0x00004024, 0x00004100, 0x00004104, 0x00004120, 0x00004124, 0x00004800,
	0x00004804, 0x00004820, 0x00004824, 0x00004900, 0x00004904, 0x00004920, 0x00004924, 0x00020000,
	0x00020004, 0x00020020, 0x00020024, 0x00020100, 0x00020104, 0x00020120, 0x00020124, 0x00020800,
	0x00020804, 0x00020820, 0x00020824, 0x00020900, 0x00020904, 0x00020920, 0x00020924, 0x00024000,
	0x00024004, 0x00024020, 0x00024024, 0x00024100, 0x00024104, 0x00024120, 0x00024124, 0x00024800,
	0x00024804, 0x00024820, 0x00024824, 0x00024900, 0x00024904, 0x00024920, 0x00024924, 0x00100000,
	0x00100004, 0x00100020, 0x00100024, 0x00100100, 0x00100104, 0x00100120, 0x00100124, 0x00100800,
	0x00100804, 0x00100820, 0x00100824, 0x00100900, 0x00100904, 0x00100920, 0x00100924, 0x00104000,
	0x00104004, 0x00104020, 0x00104024, 0x00104100, 0x00104104, 0x00104120, 0x00104124, 0x00104800,
	0x00104804, 0x00104820, 0x00104824, 0x00104900, 0x00104904, 0x00104920, 0x00104924, 0x00120000,
	0x00120004, 0x00120020, 0x00120024, 0x00120100, 0x00120104, 0x00120120, 0x00120124, 0x00120800,
	0x00120804, 0x00120820, 0x00120824, 0x00120900, 0x00120904, 0x00120920, 0x00120924, 0x00124000,
	0x00124004, 0x00124020, 0x00124024, 0x00124100, 0x00124104, 0x00124120, 0x00124124, 0x00124800,
	0x00124804, 0x00124820, 0x00124824, 0x00124900, 0x00124904, 0x00124920, 0x00124924, 0x00800000,
	0x00800004, 0x00800020, 0x00800024, 0x00800100, 0x00800104, 0x00800120, 0x00800124, 0x00800800,
	0x00800804, 0x00800820, 0x00800824, 0x00800900, 0x00800904, 0x00800920, 0x00800924, 0x00804000,
	0x00804004, 0x00804020, 0x00804024, 0x00804100, 0x00804104, 0x00804120, 0x00804124, 0x00804800,
	0x00804804, 0x00804820, 0x00804824, 0x00804900, 0x00804904, 0x00804920, 0x00804924, 0x00820000,
	0x00820004, 0x00820020, 0x00820024, 0x00820100, 0x00820104, 0x00820120, 0x00820124, 0x00820800,
	0x00820804, 0x00820820, 0x00820824, 0x00820900, 0x00820904, 0x00820920, 0x00820924, 0x00824000,
	0x00824004, 0x00824020, 0x00824024, 0x00824100, 0x00824104, 0x00824120, 0x00824124, 0x00824800,
	0x00824804, 0x00824820, 0x00824824, 0x00824900, 0x00824904, 0x00824920, 0x00824924, 0x00900000,
	0x00900004, 0x00900020, 0x00900024, 0x00900100, 0x00900104, 0x00900120, 0x00900124, 0x00900800,
	0x00900804, 0x00900820, 0x00900824, 0x00900900, 0x00900904, 0x00900920, 0x00900924, 0x00904000,
	0x00904004, 0x00904020, 0x00904024, 0x00904100, 0x00904104, 0x00904120, 0x00904124, 0x00904800,
	0x00904804, 0x00904820, 0x00904824, 0x00904900, 0x00904904, 0x00904920, 0x00904924, 0x00920000,
	0x00920004, 0x00920020, 0x00920024, 0x00920100, 0x00920104, 0x00920120, 0x00920124, 0x00920800,
	0x00920804, 0x00920820, 0x00920824, 0x00920900, 0x00920904, 0x00920920, 0x00920924, 0x00924000,
	0x00924004, 0x00924020, 0x00924024, 0x00924100, 0x00924104, 0x00924120, 0x00924124, 0x00924800,
	0x00924804, 0x00924820, 0x00924824, 0x00924900, 0x00924904, 0x00924920, 0x00924924
};

__device__ uint64 mortonEncode_LUT(const glm::vec3& data, const BoundingBox& box){

	glm::dvec3 temp = (((glm::dvec3(data) - glm::dvec3(box.origin)) / glm::dvec3(box.extent))/2.0)+0.5;

	//uint max = powf(2, 21) - 1;

	uint x = uint(temp.x*UINT_MAX);
	uint y = uint(temp.y*UINT_MAX);
	uint z = uint(temp.z*UINT_MAX);



	uint64 answer = 0;
	answer = morton256_z[(z >> 16) & 0xFF] | // we start by shifting the third byte, since we only look at the first 21 bits
		morton256_y[(y >> 16) & 0xFF] |
		morton256_x[(x >> 16) & 0xFF];
	answer = answer << 48 | morton256_z[(z >> 8) & 0xFF] | // shifting second byte
		morton256_y[(y >> 8) & 0xFF] |
		morton256_x[(x >> 8) & 0xFF];
	answer = answer << 24 |
		morton256_z[(z)& 0xFF] | // first byte
		morton256_y[(y)& 0xFF] |
		morton256_x[(x)& 0xFF];
	return answer;
}


__global__ void GenerateMortonCodes(const uint n, KernelArray<uint64> mortonCodes, KernelArray<Face*> faceList, KernelArray<Object*> objectList, const BoundingBox box){

	uint index = getGlobalIdx_1D_1D();

	if (index < n){
		Object* current = faceList[index]->objectPointer;
		Face* face = faceList[index];

		glm::vec3 centroid = (current->vertices[face->indices.x].position + current->vertices[face->indices.y].position + current->vertices[face->indices.z].position) / 3.0f;
		mortonCodes[index] = mortonEncode_LUT(centroid, box);
		
	}
}

__global__ void FillBool(const uint n,KernelArray<bool> jobs , KernelArray<bool> fjobs,  KernelArray<Face*> faces,  KernelArray<uint> objIds, KernelArray<Object*> objects){


	uint index = getGlobalIdx_1D_1D();


	if (index < n){
		if (objects[objIds[index]-1]->requestRemoval){
			jobs[index] = true;
		}
		else{
			jobs[index] = false;
		}
		if (faces[index]->objectPointer->requestRemoval){
			fjobs[index] = true;
		}
		else{
			fjobs[index] = false;
		}
	}
}

__global__ void GetFace(const uint n, KernelArray<uint> objIds, KernelArray<Object*> objects, KernelArray<Face*> faces, const uint offset){


	uint index = getGlobalIdx_1D_1D();


	if (index >= n){
		return;
	}

	Object* obj = objects[objIds[offset+index] - 1];
	faces[offset + index] = obj->faces + (index - obj->localSceneIndex);
	faces[offset + index]->objectPointer = obj;

}


//add all new objects into the scene's arrays
__host__ bool Scene::Compile(){

	uint amountToRemove = objectsToRemove.size();

	if (newFaceAmount > 0 || amountToRemove>0){

		//bitSetup only has the first element of each object flagged
		//this extends that length and copies the previous results as well

		uint newSize = compiledSize + newFaceAmount;
		uint indicesToRemove = 0;
		uint removedOffset = 0;
		if (amountToRemove>0){

				bool* markers;
				bool* faceMarkers;
				cudaMallocManaged(&markers, compiledSize * sizeof(bool));
				cudaMallocManaged(&faceMarkers, compiledSize * sizeof(bool));


				thrust::device_ptr<bool> tempPtr = thrust::device_pointer_cast(markers);
				thrust::device_ptr<bool> faceTempPtr = thrust::device_pointer_cast(faceMarkers);


				//variables from the scene to the kernal
				KernelArray<bool> boolJobs = KernelArray<bool>(markers, compiledSize);
				KernelArray<bool> faceBoolJobs = KernelArray<bool>(faceMarkers, compiledSize);
				KernelArray<Face*>faceIdsInput = KernelArray<Face*>(faceIds, compiledSize);

				KernelArray<uint> objIdsInput = KernelArray<uint>(objIds, compiledSize);
			
				KernelArray<Object*> objectsInput = KernelArray<Object*>(objectList, compiledSize);
			
			
				uint blockSize = 64;
				uint gridSize = (compiledSize + blockSize - 1) / blockSize;
			
				//fill the mask with 1s or 0s
				FillBool << <gridSize, blockSize >> >(compiledSize, boolJobs, faceBoolJobs, faceIdsInput, objIdsInput, objectsInput);
			
				CudaCheck(cudaDeviceSynchronize());
			
			
				//remove the requested
				thrust::device_ptr<bool> bitPtr = thrust::device_pointer_cast(objectBitSetup);
			
				thrust::device_ptr<bool> newEnd = thrust::remove_if(bitPtr, bitPtr + compiledSize, tempPtr, thrust::identity<bool>());
				CudaCheck(cudaDeviceSynchronize());

				indicesToRemove = bitPtr + compiledSize - newEnd;
				newSize = newSize-indicesToRemove;
				//objpointers
				thrust::device_ptr<uint> objPtr = thrust::device_pointer_cast(objIds);
			
				thrust::remove_if(objPtr, objPtr + compiledSize, tempPtr, thrust::identity<bool>());
				CudaCheck(cudaDeviceSynchronize());

				//faces
				thrust::device_ptr<Face*> facePtr = thrust::device_pointer_cast(faceIds);

				thrust::remove_if(facePtr, facePtr + compiledSize, faceTempPtr, thrust::identity<bool>());
				CudaCheck(cudaDeviceSynchronize());
			
				//actual object list
				thrust::device_ptr<Object*> objectsPtr = thrust::device_pointer_cast(objectList);
			
				thrust::remove_if(objectsPtr, objectsPtr + objectsSize, is_scheduled());

				CudaCheck(cudaDeviceSynchronize());
				cudaFree(markers);
				cudaFree(faceMarkers);
		}

		if(newFaceAmount > 0){

			if (allocatedSize<newSize){
				Face** faceTemp;
				uint* objTemp;
				bool* objectBitSetupTemp;

				allocatedSize = glm::max(uint(allocatedSize * 1.5f), newSize);

				cudaMallocManaged(&faceTemp, allocatedSize * sizeof(Face*));
				cudaMallocManaged(&objTemp, allocatedSize * sizeof(uint));
				cudaMallocManaged(&objectBitSetupTemp, allocatedSize * sizeof(bool));
				cudaFree(mortonCodes);
				cudaMallocManaged(&mortonCodes, allocatedSize * sizeof(uint64));

				cudaMemcpy(faceTemp, faceIds, compiledSize*sizeof(Face*), cudaMemcpyDefault);
				cudaFree(faceIds);
				faceIds = faceTemp;

				cudaMemcpy(objTemp, objIds, compiledSize*sizeof(uint), cudaMemcpyDefault);
				cudaFree(objIds);
				objIds = objTemp;

				cudaMemcpy(objectBitSetupTemp, objectBitSetup, compiledSize*sizeof(bool), cudaMemcpyDefault);
				cudaFree(objectBitSetup);
				objectBitSetup = objectBitSetupTemp;

			}

			CudaCheck(cudaDeviceSynchronize());
			removedOffset = compiledSize - indicesToRemove;
			//for each new object, (all at the end of the array) fill with falses.
			thrust::device_ptr<bool> bitPtr = thrust::device_pointer_cast(objectBitSetup);
			thrust::fill(bitPtr + removedOffset, bitPtr + newSize, (bool)false);

			CudaCheck(cudaDeviceSynchronize());

		}

		
		CudaCheck(cudaDeviceSynchronize());

		//flag the first and setup state of life (only time iteration through objects should be done)
		uint l = 0;
		for (uint i = 0; i < objectsSize; i++){
			if (!objectList[i]->ready){
				objectBitSetup[l] = true;
				objectList[i]->ready = true;
			}
			objectList[i]->localSceneIndex = l;
			l += objectList[i]->faceAmount;
		}

		if (newFaceAmount > 0){

			thrust::device_ptr<bool> bitPtr = thrust::device_pointer_cast(objectBitSetup);
			thrust::device_ptr<uint> objPtr = thrust::device_pointer_cast(objIds);
			CudaCheck(cudaDeviceSynchronize());

			thrust::inclusive_scan(bitPtr, bitPtr + newSize, objPtr);
			CudaCheck(cudaDeviceSynchronize());


			KernelArray<Face*> faceInput = KernelArray<Face*>(faceIds, newSize);
			KernelArray<uint> objIdsInput = KernelArray<uint>(objIds, newSize);
			KernelArray<Object*> objectsInput = KernelArray<Object*>(objectList, newSize);


			uint blockSize = 64;
			uint gridSize = ((newSize - removedOffset) + blockSize - 1) / blockSize;

			GetFace << <gridSize, blockSize >> >(newSize - removedOffset, objIdsInput, objectsInput, faceInput, removedOffset);
			CudaCheck(cudaDeviceSynchronize());

		}
		CudaCheck(cudaDeviceSynchronize());

	//change the indice count of the scene
	compiledSize = newSize;
	newFaceAmount = 0;
	objectsToRemove.clear();
	return true;
		
	}
	else{
		return false;
	}

		
}


__host__ void Scene::Build(){
	
	bool b = Compile();

		//calculate the morton code for each triangle

		uint blockSize = 64;
		uint gridSize = (compiledSize + blockSize - 1) / blockSize;

		KernelArray<Face*> faceInput = KernelArray<Face*>(faceIds, compiledSize);
		KernelArray<uint64> mortonInput = KernelArray<uint64>(mortonCodes, compiledSize);

		KernelArray<Object*> objectsInput = KernelArray<Object*>(objectList, compiledSize);

		CudaCheck(cudaDeviceSynchronize());

		GenerateMortonCodes << <gridSize, blockSize >> >(compiledSize, mortonInput, faceInput, objectsInput, sceneBox);

		thrust::device_ptr<uint64_t> keys = thrust::device_pointer_cast(mortonCodes);
		thrust::device_ptr<Face*> values = thrust::device_pointer_cast(faceIds);

		CudaCheck(cudaDeviceSynchronize());

		cudaEvent_t start, stop;
		float time;
		cudaEventCreate(&start);
		cudaEventCreate(&stop);
		cudaEventRecord(start, 0);

		//thrust::sort_by_key(keys, keys + compiledSize, values);            //I assume this is broken with this build setup, is ok though, will try to phase out thrust in a final build

		//simple bubblesort to bide the time
		bool swapped = true;
		int j = 0;
		uint64 tmp;
		Face* ftmp;
		while (swapped) {
			swapped = false;
			j++;
			for (int i = 0; i < compiledSize - j; i++) {
				if (mortonCodes[i] > mortonCodes[i + 1]) {
					tmp = mortonCodes[i];
					mortonCodes[i] = mortonCodes[i + 1];
					mortonCodes[i + 1] = tmp;
					
					ftmp = faceIds[i];
					faceIds[i] = faceIds[i + 1];
					faceIds[i + 1] = ftmp;

					swapped = true;
				}
			}
		}


		CudaCheck(cudaDeviceSynchronize());

		cudaEventRecord(stop, 0);
		cudaEventSynchronize(stop);
		cudaEventElapsedTime(&time, start, stop);
		cudaEventDestroy(start);
		cudaEventDestroy(stop);

		std::cout << "     Sorting Execution: " << time << "ms" << std::endl;
	/*	for (int i = 0; i < compiledSize;i++){
			std::cout << mortonCodes[i] << std::endl;
		}

		CudaCheck(cudaDeviceSynchronize());*/

		bvh->Build(compiledSize);

		//CudaCheck(cudaDeviceSynchronize());

		//for (int i = 0; i < compiledSize - 1; i++){
		//		/*std::cout << bvh->GetRoot()[i].box.origin.x << " " << bvh->GetRoot()[i].box.origin.y << " " << bvh->GetRoot()[i].box.origin.z << std::endl;
		//		std::cout << bvh->GetRoot()[i].box.extent.x << " " << bvh->GetRoot()[i].box.extent.y << " " << bvh->GetRoot()[i].box.extent.z << std::endl;
		//		std::cout << std::endl;*/
		//	std::cout << bvh->GetRoot()[i].childLeft <<" "<< bvh->GetRoot()[i].childRight << std::endl;
		//}

		//CudaCheck(cudaDeviceSynchronize());



}

CUDA_FUNCTION glm::vec3 PositionAlongRay(const Ray& ray, const float& t) {
	return ray.origin + t * ray.direction;
}
CUDA_FUNCTION glm::vec3 computeBackgroundColor(const glm::vec3& direction) {
	float position = (glm::dot(direction, normalize(glm::vec3(-0.5, 0.5, -1.0))) + 1) / 2.0f;
	return (1.0f - position) * glm::vec3(0.5f, 0.5f, 1.0f) + position * glm::vec3(0.7f, 0.7f, 1.0f);
	//return glm::vec3(0.0f, 0.0f, 0.0f);
}

CUDA_FUNCTION bool FindTriangleIntersect(const glm::vec3& a, const glm::vec3& edge1, const glm::vec3& edge2,
	const Ray& ray,
	float& t,const float& tMax, float& bary1, float& bary2)
{

	glm::vec3 pvec = glm::cross(ray.direction, edge2);
	float det = glm::dot(edge1, pvec);
	if (det > -EPSILON && det < EPSILON){
		return false;
	}
	float inv_det = 1.0f / det;

	glm::vec3 tvec = ray.origin - a;
	bary1 = glm::dot(tvec, pvec) * inv_det;

	glm::vec3 qvec = glm::cross(tvec, edge1);
	bary2 = glm::dot(ray.direction, qvec) * inv_det;

	t = glm::dot(edge2, qvec) * inv_det;

	return t > EPSILON &&t < tMax && (bary1 >= 0.0f && bary2 >= 0.0f && (bary1 + bary2) <= 1.0f);

}

CUDA_FUNCTION bool AABBIntersect(const BoundingBox& box, const glm::vec3& o, const glm::vec3& dInv, const float& t0,  float& t1){

	glm::vec3 boxMax = box.origin + box.extent;
	glm::vec3 boxMin = box.origin - box.extent;

	float temp1 = (boxMin.x - o.x)*dInv.x;
	float temp2 = (boxMax.x - o.x)*dInv.x;

	float tmin = glm::min(temp1, temp2);
	float tmax = glm::max(temp1, temp2);

	temp1 = (boxMin.y - o.y)*dInv.y;
	temp2 = (boxMax.y - o.y)*dInv.y;

	tmin = glm::max(tmin, glm::min(temp1, temp2));
	tmax = glm::min(tmax, glm::max(temp1, temp2));

	temp1 = (boxMin.z - o.z)*dInv.z;
	temp2 = (boxMax.z - o.z)*dInv.z;

	tmin = glm::max(tmin, glm::min(temp1, temp2));
	tmax = glm::min(tmax, glm::max(temp1, temp2));

	float tTest = t1;
	t1 = tmin;
	return tmax >= glm::max(t0, tmin) && tmin < tTest;
}

__device__ bool FindBVHIntersect(const Ray& ray, BVH* bvh, float& bestT, glm::vec3& bestNormal, Material*& mat){

	bool intersected = false;

	Node* stack[BVH_STACK_SIZE];

	uint stackIdx = 0;
	
	glm::vec3 dirInverse = 1.0f / ray.direction;

	float t = bestT;
	if (AABBIntersect(bvh->GetRoot()->box, ray.origin, dirInverse, 0.0f, t)){
		stack[stackIdx++] = bvh->GetRoot();
	}

	while (stackIdx>0) {

		// pop a BVH node

		Node* node = stack[--stackIdx];

		//inner node

		if (bvh->IsLeaf(node)) {

			glm::uvec3 face = node->faceID->indices;

			glm::vec3 xIndPos = node->faceID->objectPointer->vertices[face.x].position;
			glm::vec3 yIndPos = node->faceID->objectPointer->vertices[face.y].position;
			glm::vec3 zIndPos = node->faceID->objectPointer->vertices[face.z].position;


			float bary1 = 0;
			float bary2 = 0;
			float tTemp;

			glm::vec3 edge1 = yIndPos - xIndPos;
			glm::vec3 edge2 = zIndPos - xIndPos;

			if (FindTriangleIntersect(xIndPos, edge1, edge2,
				ray,
				tTemp, bestT, bary1, bary2)){

				bestT = tTemp;
				/*	glm::vec3 norm1 = current->vertices[face.x].normal;
				glm::vec3 norm2 = current->vertices[face.y].normal;
				glm::vec3 norm3 = current->vertices[face.z].normal;*/
				bestNormal = glm::normalize(glm::cross(edge1, edge2));
				//bestNormal =glm::normalize( (norm3*bary2) + (norm2*bary1) + (norm1*(1.0f - bary1 - bary2)));
				mat = node->faceID->materialPointer;
				intersected = true;
			}

			
		}
		//outer node
		else {
			Node* first = node->childRight;
			Node* second = node->childLeft;

			float tL = bestT;
			float tR = bestT;
			bool t1 = AABBIntersect(second->box, ray.origin, dirInverse, 0.0f, tL);
			bool t2 = AABBIntersect(first->box, ray.origin, dirInverse, 0.0f, tR);

			

			if (t1&&t2&&tL<tR){
				Node* temp = first;
				first = second;
				second = temp;

			}
			if (t1){
				stack[stackIdx++] = second; // right child node index
				if (stackIdx==BVH_STACK_SIZE){
					return false;
				}
			}
			if (t2){
				stack[stackIdx++] = first; // left child node index
				if (stackIdx == BVH_STACK_SIZE){
					return false;
				}
			}
		}
	}


	return intersected;
}


__device__ glm::vec3 Scene::IntersectColour(Ray& ray, curandState& randState)const{

	float bestT = 400000000.0f;

	glm::vec3 bestNormal = glm::vec3(0.0f, 0.0f, 0.0f);

	//glm::vec4 accumulation;

	Material* mat;
	bool intersected = FindBVHIntersect(ray, bvh, bestT, bestNormal, mat);



	if (!intersected){

		ray.active = false;
		return  glm::vec3(ray.storage)*computeBackgroundColor(ray.direction);
	}
	else{
		glm::vec3 biasVector = (RAY_BIAS_DISTANCE * bestNormal);

		glm::vec3 bestIntersectionPoint = PositionAlongRay(ray, bestT);


		glm::vec3 accumulation = glm::vec3(ray.storage * mat->emit);

		ray.storage *= mat->diffuse;


		////glm::vec3 incident = -ray.direction;

		glm::vec3 orientedNormal = glm::dot(bestNormal, ray.direction) < 0 ? bestNormal : bestNormal * -1.0f;

		float r1 = 2 * PI * curand_uniform(&randState);
		float r2 = curand_uniform(&randState);
		float r2s = sqrtf(r2);

		glm::vec3 u = glm::normalize(glm::cross((glm::abs(orientedNormal.x) > .1 ? glm::vec3(0, 1, 0) : glm::vec3(1, 0, 0)), orientedNormal));
		glm::vec3 v = glm::cross(orientedNormal, u);

		ray.origin = bestIntersectionPoint + biasVector;
		ray.direction = glm::normalize(u*cos(r1)*r2s + v*sin(r1)*r2s + orientedNormal*sqrtf(1 - r2));

		return accumulation;

		//return glm::vec3(1.0f,0.0f,0.0f);
	}
}

__host__ uint Scene::AddObject(Object* obj){

	//if the size of objects stores increases, double the available size pool;
	if (objectsSize == allocatedObjects){

		Object** objectsTemp;
		allocatedObjects *= 2;

		if (allocatedObjects==0){
			allocatedObjects = 1;
		}

		cudaMallocManaged(&objectsTemp, allocatedObjects * sizeof(Object*));
		
		cudaMemcpy(objectsTemp, objectList, objectsSize*sizeof(Object*), cudaMemcpyDefault);
		cudaFree(objectList);
		objectList = objectsTemp;
	}
	
	
	//update the scene's bounding volume
	glm::vec3 max = sceneBox.origin + sceneBox.extent;
	glm::vec3 min = sceneBox.origin - sceneBox.extent;

	glm::vec3 objMax = obj->box.origin + obj->box.extent;
	glm::vec3 objMin = obj->box.origin - obj->box.extent;

	glm::vec3 newMax = glm::max(max, objMax);
	glm::vec3 newMin = glm::min(min, objMin);
	
	sceneBox.origin = ((newMax - newMin) / 2.0f) + newMin;
	sceneBox.extent = sceneBox.origin - newMin;

	//add the reference as the new object and increase the object count by 1
	CudaCheck(cudaDeviceSynchronize());
	objectList[objectsSize] = obj;
	objectsSize++;
	newFaceAmount += obj->faceAmount;
	return 0;
}

__host__ bool Scene::RemoveObject(const uint& tag){
	objectRemoval[tag] = true;
	return true;
}